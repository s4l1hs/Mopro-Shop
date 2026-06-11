package refund

import (
	"context"
	"testing"

	"github.com/mopro/platform/internal/eventbus"
)

// settleFunc adapts a func to the Service interface.
type settleFunc func(context.Context, RefundEvent) error

func (f settleFunc) SettleRefund(ctx context.Context, ev RefundEvent) error { return f(ctx, ev) }

// TestHandleRefunded_DecodesProducerWireFormat pins the consumer to the EXACT JSON
// order.SellerApprove emits. The literal below mirrors internal/order/returns.go's
// returnRefundedPayload json tags — if either side renames a field, this fails (the
// cross-binary contract guard the unit tests on each side can't catch alone).
func TestHandleRefunded_DecodesProducerWireFormat(t *testing.T) {
	const producerJSON = `{"return_id":5,"order_id":1,"user_id":7,"refund_amount_minor":8000,"currency":"TRY","market":"TR"}`

	var got RefundEvent
	svc := settleFunc(func(_ context.Context, ev RefundEvent) error { got = ev; return nil })

	if err := handleRefunded(context.Background(), svc, eventbus.Event{Payload: []byte(producerJSON)}); err != nil {
		t.Fatalf("handleRefunded: %v", err)
	}
	want := RefundEvent{ReturnID: 5, OrderID: 1, UserID: 7, RefundAmountMinor: 8000, Market: "TR"}
	if got != want {
		t.Errorf("decoded %+v, want %+v", got, want)
	}
}

// Market falls back to the event envelope when absent from the payload.
func TestHandleRefunded_MarketFallsBackToEnvelope(t *testing.T) {
	const noMarketJSON = `{"return_id":5,"order_id":1,"user_id":7,"refund_amount_minor":8000,"currency":"TRY"}`
	var got RefundEvent
	svc := settleFunc(func(_ context.Context, ev RefundEvent) error { got = ev; return nil })
	if err := handleRefunded(context.Background(), svc, eventbus.Event{Market: "TR", Payload: []byte(noMarketJSON)}); err != nil {
		t.Fatalf("handleRefunded: %v", err)
	}
	if got.Market != "TR" {
		t.Errorf("market=%q want TR (envelope fallback)", got.Market)
	}
}
