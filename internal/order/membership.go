package order

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// AC-05 phase 1: the membership tier is a PURE DERIVED READ-MODEL over the
// user's order history — it stores no balance, mints no coin, and never touches
// postgres-ledger. Tiers themselves are reference data
// (ref_schema.membership_tiers, migration 0094), never code constants, so
// adding a market or moving a threshold is seed-only.
//
// Kept as a separate interface from Service (the ReturnService precedent) so
// the existing order Service mocks stay untouched.

// MembershipWindowDays is the rolling qualification window. Qualifying
// activity = DELIVERED orders within the window (cancelled/refunded excluded —
// deterministic and replayable).
const MembershipWindowDays = 365

// ErrNoMembershipTiers is returned when ref data has no active tiers for the
// market (a provisioning error — the seed always includes the rank-1 base tier).
var ErrNoMembershipTiers = errors.New("order: no membership tiers for market")

// MembershipTierDef is one rung of the ref-data ladder.
type MembershipTierDef struct {
	Code          string `json:"code"`
	Rank          int    `json:"rank"`
	Currency      string `json:"currency"`
	MinSpendMinor int64  `json:"min_spend_minor"`
	MinOrders     int    `json:"min_orders"`
}

// Membership is the derived tier state for one user.
type Membership struct {
	Tier       string `json:"tier"`
	Rank       int    `json:"rank"`
	WindowDays int    `json:"window_days"`
	SpendMinor int64  `json:"spend_minor"`
	OrderCount int    `json:"order_count"`
	Currency   string `json:"currency"`
	// Next-rung targets; nil at the top tier.
	NextTier          *string `json:"next_tier,omitempty"`
	NextMinSpendMinor *int64  `json:"next_min_spend_minor,omitempty"`
	NextMinOrders     *int    `json:"next_min_orders,omitempty"`
}

// MembershipRepository is the storage surface for the tier read-model: one
// single-schema aggregate over order_schema.orders + one ref_schema read (the
// explicitly allowed §5 shared-read exception).
type MembershipRepository interface {
	// UserOrderStats sums total_minor and counts the user's DELIVERED orders
	// created since `since`.
	UserOrderStats(ctx context.Context, userID int64, since time.Time) (spendMinor int64, count int, err error)
	// ListMembershipTiers returns the market's active ladder, rank ASC.
	ListMembershipTiers(ctx context.Context, market string) ([]MembershipTierDef, error)
}

// MembershipService derives a user's membership tier.
type MembershipService interface {
	GetMembershipTier(ctx context.Context, userID int64, market string) (Membership, error)
}

type membershipService struct {
	repo MembershipRepository
	now  func() time.Time
}

// NewMembershipService builds the tier read-model service.
func NewMembershipService(repo MembershipRepository) MembershipService {
	return &membershipService{repo: repo, now: func() time.Time { return time.Now().UTC() }}
}

// GetMembershipTier: highest-rank tier whose spend AND order thresholds are
// both met; next_* describes the following rung (omitted at the top).
func (s *membershipService) GetMembershipTier(ctx context.Context, userID int64, market string) (Membership, error) {
	tiers, err := s.repo.ListMembershipTiers(ctx, market)
	if err != nil {
		return Membership{}, fmt.Errorf("order.membership: tiers: %w", err)
	}
	if len(tiers) == 0 {
		return Membership{}, ErrNoMembershipTiers
	}

	since := s.now().AddDate(0, 0, -MembershipWindowDays)
	spend, count, err := s.repo.UserOrderStats(ctx, userID, since)
	if err != nil {
		return Membership{}, fmt.Errorf("order.membership: stats: %w", err)
	}

	// tiers are rank ASC; walk up while both thresholds hold.
	current := tiers[0]
	var next *MembershipTierDef
	for i := 1; i < len(tiers); i++ {
		t := tiers[i]
		if spend >= t.MinSpendMinor && count >= t.MinOrders {
			current = t
			continue
		}
		next = &tiers[i]
		break
	}

	m := Membership{
		Tier:       current.Code,
		Rank:       current.Rank,
		WindowDays: MembershipWindowDays,
		SpendMinor: spend,
		OrderCount: count,
		Currency:   current.Currency,
	}
	if next != nil {
		m.NextTier = &next.Code
		m.NextMinSpendMinor = &next.MinSpendMinor
		m.NextMinOrders = &next.MinOrders
	}
	return m, nil
}
