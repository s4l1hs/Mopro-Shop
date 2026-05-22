package cashback

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/pkg/timex"
)

// capturePlanInsertRepo embeds mockCashbackRepo and captures the Plan passed to InsertPlan.
type capturePlanInsertRepo struct {
	mockCashbackRepo
	inserted Plan
}

func (c *capturePlanInsertRepo) InsertPlan(_ context.Context, _ pgx.Tx, p Plan) (Plan, error) {
	c.inserted = p
	p.ID = 42
	return p, nil
}

// TestCreatePlanForOrder_PopulatesProductFields verifies that product_id,
// product_title, and product_image_url are captured from OrderDeliveredEvent
// and persisted on the cashback Plan.
func TestCreatePlanForOrder_PopulatesProductFields(t *testing.T) {
	repo := &capturePlanInsertRepo{}
	calLoader := timex.NewStaticCalendarLoader(map[string]timex.Calendar{
		"TR": {},
	})
	svc := NewService(repo, &mockCronOutbox{}, calLoader, "TRY_COIN", &mockWalletPoster{}, nil)

	ev := OrderDeliveredEvent{
		OrderID:     99,
		UserID:      1,
		DeliveredAt: time.Now(),
		Market:      "TR",
		Currency:    "TRY",
		Items: []CommissionSnapshotItem{
			{
				VariantID:             10,
				SellerID:              5,
				CategoryID:            3,
				Qty:                   1,
				UnitPriceMinor:        10000,
				CommissionPctBps:      2000,
				KdvPctBps:             200,
				CommissionAmountMinor: 2000,
				KdvAmountMinor:        40,
				SellerNetMinor:        7960,
			},
		},
		ProductID:       7,
		ProductTitle:    "Kırmızı Elbise",
		ProductImageURL: "https://cdn.example.com/img/abc.jpg",
	}

	if err := svc.CreatePlanForOrder(context.Background(), ev); err != nil {
		t.Fatalf("CreatePlanForOrder: %v", err)
	}

	p := repo.inserted
	if p.ProductID != 7 {
		t.Errorf("ProductID: got %d, want 7", p.ProductID)
	}
	if p.ProductTitle != "Kırmızı Elbise" {
		t.Errorf("ProductTitle: got %q, want %q", p.ProductTitle, "Kırmızı Elbise")
	}
	if p.ProductImageURL != "https://cdn.example.com/img/abc.jpg" {
		t.Errorf("ProductImageURL: got %q", p.ProductImageURL)
	}
}
