package order_test

import (
	"context"
	"errors"
	"testing"

	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/payment"

	"github.com/jackc/pgx/v5"
)

// fakeMembership is a stand-in tier read-model: it returns a fixed rank (or an
// error, to exercise the fail-closed path). The order module owns MembershipService
// (same package), so this gating is in-module — no cross-schema path (§5).
type fakeMembership struct {
	rank int
	err  error
}

func (f fakeMembership) GetMembershipTier(_ context.Context, _ int64, _ string) (order.Membership, error) {
	if f.err != nil {
		return order.Membership{}, f.err
	}
	return order.Membership{Tier: "x", Rank: f.rank}, nil
}

// TestTierCoupon_EligibilityGate is the membership-benefits keystone test: a
// tier-exclusive coupon (ELITE15, min_tier_rank=3) gates ELIGIBILITY only.
//
//   - eligible (rank ≥ 3): the coupon applies, the CHARGED total reflects it
//     (display==charge — the saga charges the gated-coupon total), and exactly one
//     redemption is recorded.
//   - ineligible (below rank / guest): the coupon is silently dropped (tier_locked),
//     the buyer pays the FULL price, and NO redemption is recorded.
//
// Default cart = variant 1 × qty 2 @ 10000, no basket discount ⇒ basketSubtotal
// 20000. ELITE15 = 15% ⇒ eligible total 17000 (discount 3000); locked total 20000.
func TestTierCoupon_EligibilityGate(t *testing.T) {
	maxRank3 := 3
	elite15 := order.Coupon{
		ID: 7, Code: "ELITE15", Kind: "percent", PercentOff: 15,
		Active: true, Market: "TR", MinTierRank: maxRank3,
	}

	cases := []struct {
		name         string
		membership   order.MembershipService
		wantCharged  int64
		wantDiscount int64
		wantRedeemed int
	}{
		{"eligible elite (rank 3) → applied + redeemed", fakeMembership{rank: 3}, 17000, 3000, 1},
		{"eligible above (rank 4) → applied + redeemed", fakeMembership{rank: 4}, 17000, 3000, 1},
		{"ineligible gold (rank 2) → locked, full price, no redemption", fakeMembership{rank: 2}, 20000, 0, 0},
		{"ineligible classic (rank 1) → locked, full price, no redemption", fakeMembership{rank: 1}, 20000, 0, 0},
		{"nil membership → fail-closed rank 1 → locked, no redemption", nil, 20000, 0, 0},
		{"membership error → fail-closed rank 1 → locked, no redemption", fakeMembership{err: errors.New("boom")}, 20000, 0, 0},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var charged int64
			var capturedOrder order.Order
			redeemed := 0
			repo := &mockRepo{
				getCouponByCodeFn: func(_ context.Context, code, _ string) (order.Coupon, error) {
					if code == "ELITE15" {
						return elite15, nil
					}
					return order.Coupon{}, order.ErrCouponNotFound
				},
				insertRedemptionFn: func(_ context.Context, _ pgx.Tx, _ order.CouponRedemption) error {
					redeemed++
					return nil
				},
				insertOrderFn: func(_ context.Context, _ pgx.Tx, o order.Order) (order.Order, error) {
					capturedOrder = o
					o.ID = 1
					return o, nil
				},
			}
			psp := &mockPSP{
				initiatePaymentFn: func(_ context.Context, req payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error) {
					charged = req.AmountMinor
					return payment.InitiatePaymentResponse{ProviderRef: req.IdempotencyKey, ThreeDSHTML: "<form/>"}, nil
				},
			}
			svc := order.NewServiceFull(repo, &mockSessionRepo{}, &mockCartSvc{}, &mockCatalogSvc{},
				&mockOutbox{}, "TR", "TRY_COIN", psp, nil, nil, nil, tc.membership)

			_, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
				UserID: 1, SessionID: "sess-tier", BuyerEmail: "a@b.c", CouponCode: "ELITE15",
			})
			if err != nil {
				t.Fatalf("InitiateCheckout: %v", err)
			}
			// display==charge: the PSP-charged amount == the persisted order total.
			if charged != tc.wantCharged {
				t.Errorf("PSP charged: got %d want %d", charged, tc.wantCharged)
			}
			if capturedOrder.TotalMinor != tc.wantCharged {
				t.Errorf("order total: got %d want %d", capturedOrder.TotalMinor, tc.wantCharged)
			}
			if capturedOrder.DiscountMinor != tc.wantDiscount {
				t.Errorf("order discount: got %d want %d", capturedOrder.DiscountMinor, tc.wantDiscount)
			}
			if redeemed != tc.wantRedeemed {
				t.Errorf("redemptions recorded: got %d want %d", redeemed, tc.wantRedeemed)
			}
		})
	}
}

// TestTierCoupon_BackwardCompat asserts a default-rank coupon (min_tier_rank=1, the
// 0106 default that every pre-0106 coupon now carries) behaves identically to
// before — it applies for a rank-1 (classic) user. 10% on 20000 ⇒ total 18000.
func TestTierCoupon_BackwardCompat(t *testing.T) {
	welcome10 := order.Coupon{
		ID: 1, Code: "WELCOME10", Kind: "percent", PercentOff: 10,
		Active: true, Market: "TR", MinTierRank: 1, // = default = everyone
	}
	var charged int64
	redeemed := 0
	repo := &mockRepo{
		getCouponByCodeFn: func(_ context.Context, _, _ string) (order.Coupon, error) { return welcome10, nil },
		insertRedemptionFn: func(_ context.Context, _ pgx.Tx, _ order.CouponRedemption) error {
			redeemed++
			return nil
		},
	}
	psp := &mockPSP{
		initiatePaymentFn: func(_ context.Context, req payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error) {
			charged = req.AmountMinor
			return payment.InitiatePaymentResponse{ProviderRef: req.IdempotencyKey, ThreeDSHTML: "<form/>"}, nil
		},
	}
	// rank-1 user; even with membership wired, a rank-1 coupon is open to all.
	svc := order.NewServiceFull(repo, &mockSessionRepo{}, &mockCartSvc{}, &mockCatalogSvc{},
		&mockOutbox{}, "TR", "TRY_COIN", psp, nil, nil, nil, fakeMembership{rank: 1})
	if _, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
		UserID: 1, SessionID: "sess-bc", BuyerEmail: "a@b.c", CouponCode: "WELCOME10",
	}); err != nil {
		t.Fatalf("InitiateCheckout: %v", err)
	}
	if charged != 18000 {
		t.Errorf("charged: got %d want 18000 (10%% off 20000)", charged)
	}
	if redeemed != 1 {
		t.Errorf("redemptions: got %d want 1", redeemed)
	}
}

// TestTierCoupon_Idempotent asserts the tier gate adds no new write surface: an
// already-completed checkout session (idempotent replay) re-assembles the existing
// orders and records NO additional redemption.
func TestTierCoupon_Idempotent(t *testing.T) {
	elite15 := order.Coupon{
		ID: 7, Code: "ELITE15", Kind: "percent", PercentOff: 15,
		Active: true, Market: "TR", MinTierRank: 3,
	}
	redeemed := 0
	repo := &mockRepo{
		getCouponByCodeFn:  func(_ context.Context, _, _ string) (order.Coupon, error) { return elite15, nil },
		insertRedemptionFn: func(_ context.Context, _ pgx.Tx, _ order.CouponRedemption) error { redeemed++; return nil },
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPendingPayment}, nil, nil
		},
	}
	// Session already exists → idempotent replay path.
	sessionRepo := &mockSessionRepo{
		findFn: func(_ context.Context, sid string) (order.CheckoutSession, error) {
			return order.CheckoutSession{ID: sid, OrderIDs: []int64{1}, Status: order.CheckoutSessionPSPInitiated}, nil
		},
	}
	svc := order.NewServiceFull(repo, sessionRepo, &mockCartSvc{}, &mockCatalogSvc{},
		&mockOutbox{}, "TR", "TRY_COIN", &mockPSP{}, nil, nil, nil, fakeMembership{rank: 3})
	if _, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
		UserID: 1, SessionID: "sess-dup", BuyerEmail: "a@b.c", CouponCode: "ELITE15",
	}); err != nil {
		t.Fatalf("InitiateCheckout (replay): %v", err)
	}
	if redeemed != 0 {
		t.Errorf("idempotent replay recorded %d redemptions, want 0", redeemed)
	}
}
