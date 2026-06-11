// Package eventbus — Registry is the single source of truth for all event type strings
// used across Mopro's Redis Streams. Any new event type MUST be added here before
// being referenced in producer or consumer code.
package eventbus

// EventStatus classifies an event type's lifecycle state.
type EventStatus string

const (
	// StatusActiveConsumed: producer live, ≥1 consumer live.
	StatusActiveConsumed EventStatus = "active_consumed"
	// StatusActiveEmittedNoConsumer: producer live, consumer planned but not yet wired.
	StatusActiveEmittedNoConsumer EventStatus = "active_emitted_no_consumer"
	// StatusActiveConsumerNoProducer: consumer live, producer not yet emitting
	// (pre-wiring state during phased rollout).
	StatusActiveConsumerNoProducer EventStatus = "active_consumer_no_producer"
	// StatusDeprecatedPendingDelete: no live call sites — scheduled for removal.
	StatusDeprecatedPendingDelete EventStatus = "deprecated_pending_delete"
)

// EventEntry describes one event type in the system.
type EventEntry struct {
	EventType       string
	ProducerModule  string
	ConsumerGroups  []string
	Status          EventStatus
	PlannedConsumer string // set when Status == active_emitted_no_consumer
	Notes           string
}

// Registry is the authoritative list of all 17 event types.
// Names here are the source of truth; all documentation must reference this file.
var Registry = []EventEntry{
	// ── ecom domain: order ────────────────────────────────────────────────────────
	{
		EventType:      "ecom.order.delivered.v1",
		ProducerModule: "internal/order",
		ConsumerGroups: []string{"fin-cashback-consumer", "fin-sellerpayout-consumer"},
		Status:         StatusActiveConsumed,
	},
	{
		EventType:       "ecom.order.paid.v1",
		ProducerModule:  "internal/order",
		ConsumerGroups:  []string{"order-ledger-poster"},
		Status:          StatusActiveConsumed,
		PlannedConsumer: "internal/notification (Phase 4.6)",
		Notes:           "Emitted by MarkPaid on Sipay webhook capture. Payload enriched (Phase 4.5c) to include seller_id, shipping_minor, items[]. order-ledger-poster posts balanced capture ledger entry.",
	},

	// ── ecom domain: return ───────────────────────────────────────────────────────
	{
		EventType:      "ecom.return.refunded.v1",
		ProducerModule: "internal/order",
		ConsumerGroups: []string{"fin-refund-consumer"},
		Status:         StatusActiveConsumed,
		Notes:          "Emitted by SellerApprove on refund settlement (approved→refunded). internal/refund mints the refund as Mopro Coin to the buyer wallet (D equity:refund_distribution ↔ C liability:wallet:user). Idempotent: ledger key refund:<return_id>.",
	},

	// ── ecom domain: payment ─────────────────────────────────────────────────────
	{
		EventType:       "ecom.payment.captured.v1",
		ProducerModule:  "internal/payment/sipay",
		ConsumerGroups:  []string{},
		Status:          StatusActiveEmittedNoConsumer,
		PlannedConsumer: "internal/commission (Phase 3.2)",
		Notes:           "Emitted from Sipay webhook handler post-DB-commit",
	},
	{
		EventType:       "ecom.payment.failed.v1",
		ProducerModule:  "internal/payment/sipay",
		ConsumerGroups:  []string{},
		Status:          StatusActiveEmittedNoConsumer,
		PlannedConsumer: "internal/notification (Phase 3.2)",
	},
	{
		EventType:       "ecom.payment.refunded.v1",
		ProducerModule:  "internal/payment/sipay",
		ConsumerGroups:  []string{},
		Status:          StatusActiveEmittedNoConsumer,
		PlannedConsumer: "internal/cashback (reversal, Phase 3.2)",
	},
	// ecom.payment.unknown.v1: defensive fallback removed in Phase 3.0 — error returned
	// before outbox emission for unknown payment event types. Entry kept for traceability.
	{
		EventType:      "ecom.payment.unknown.v1",
		ProducerModule: "internal/payment/sipay",
		ConsumerGroups: []string{},
		Status:         StatusDeprecatedPendingDelete,
		Notes:          "Removed Phase 3.0: unknown type now returns an error before outbox insertion",
	},

	// ── ecom domain: seller ───────────────────────────────────────────────────────
	{
		EventType:      "ecom.seller.psp_onboarded.v1",
		ProducerModule: "internal/seller",
		ConsumerGroups: []string{"fin-sellerpayout-psp-onboarded"},
		Status:         StatusActiveConsumerNoProducer,
		Notes:          "Consumer wired; seller-module producer not yet emitting",
	},
	{
		EventType:      "ecom.seller.fraud_hold_set.v1",
		ProducerModule: "internal/antifraud",
		ConsumerGroups: []string{"fin-sellerpayout-fraud-hold"},
		Status:         StatusActiveConsumerNoProducer,
		Notes:          "Consumer wired; antifraud-module producer not yet emitting",
	},

	// ── fin domain: cashback ─────────────────────────────────────────────────────
	{
		EventType:       "fin.cashback.plan.created.v1",
		ProducerModule:  "internal/cashback",
		ConsumerGroups:  []string{},
		Status:          StatusActiveEmittedNoConsumer,
		PlannedConsumer: "internal/notification (Phase 3.2)",
	},
	{
		EventType:       "fin.cashback.payment.posted.v1",
		ProducerModule:  "internal/wallet",
		ConsumerGroups:  []string{},
		Status:          StatusActiveEmittedNoConsumer,
		PlannedConsumer: "internal/notification (Phase 3.2)",
	},
	// fin.cashback.reversal.posted.v1: switch case had zero call sites — deleted Phase 3.0.
	{
		EventType:      "fin.cashback.reversal.posted.v1",
		ProducerModule: "internal/wallet",
		ConsumerGroups: []string{},
		Status:         StatusDeprecatedPendingDelete,
		Notes:          "Removed Phase 3.0: outboxEventType switch case had no production call sites",
	},

	// ── fin domain: seller payout ────────────────────────────────────────────────
	{
		EventType:       "fin.seller.payout.batch.paid.v1",
		ProducerModule:  "internal/wallet",
		ConsumerGroups:  []string{},
		Status:          StatusActiveEmittedNoConsumer,
		PlannedConsumer: "internal/notification (Phase 3.2)",
		Notes:           "Renamed from fin.seller.payout.posted.v1 in Phase 3.0",
	},
	// fin.seller.payout.posted.v1: renamed to fin.seller.payout.batch.paid.v1 Phase 3.0.
	{
		EventType:      "fin.seller.payout.posted.v1",
		ProducerModule: "internal/wallet",
		ConsumerGroups: []string{},
		Status:         StatusDeprecatedPendingDelete,
		Notes:          "Renamed Phase 3.0 → fin.seller.payout.batch.paid.v1",
	},

	// ── fin domain: commission ───────────────────────────────────────────────────
	// fin.commission.accrual.posted.v1: switch case had zero call sites — deleted Phase 3.0.
	{
		EventType:      "fin.commission.accrual.posted.v1",
		ProducerModule: "internal/wallet",
		ConsumerGroups: []string{},
		Status:         StatusDeprecatedPendingDelete,
		Notes:          "Removed Phase 3.0: outboxEventType switch case had no production call sites",
	},

	// ── fin domain: treasury / FX ────────────────────────────────────────────────
	// fin.fx.outbound.posted.v1 / fin.fx.inbound.posted.v1: zero call sites — deleted Phase 3.0.
	{
		EventType:      "fin.fx.outbound.posted.v1",
		ProducerModule: "internal/wallet",
		ConsumerGroups: []string{},
		Status:         StatusDeprecatedPendingDelete,
		Notes:          "Removed Phase 3.0: outboxEventType switch case had no production call sites",
	},
	{
		EventType:      "fin.fx.inbound.posted.v1",
		ProducerModule: "internal/wallet",
		ConsumerGroups: []string{},
		Status:         StatusDeprecatedPendingDelete,
		Notes:          "Removed Phase 3.0: outboxEventType switch case had no production call sites",
	},

	// ── fin domain: ledger fallback ──────────────────────────────────────────────
	{
		EventType:      "fin.ledger.posted.v1",
		ProducerModule: "internal/wallet",
		ConsumerGroups: []string{},
		Status:         StatusActiveEmittedNoConsumer,
		Notes:          "Default fallback for unclassified tx types; no consumer planned",
	},

	// ── fin domain: reconciliation ───────────────────────────────────────────────
	{
		EventType:      "fin.reconciliation.drift_critical.v1",
		ProducerModule: "internal/reconcile",
		ConsumerGroups: []string{"notification-reconcile-drift"},
		Status:         StatusActiveConsumed,
	},

	// ── ecom domain: identity ─────────────────────────────────────────────────
	// All identity events are emitted; no consumers wired yet (Phase 4.2a).
	{
		EventType:      "ecom.user.created.v1",
		ProducerModule: "internal/identity",
		ConsumerGroups: []string{},
		Status:         StatusActiveEmittedNoConsumer,
		Notes:          "Emitted on first OTP verify (account creation). Future: welcome notification.",
	},
	{
		EventType:      "ecom.user.updated.v1",
		ProducerModule: "internal/identity",
		ConsumerGroups: []string{},
		Status:         StatusActiveEmittedNoConsumer,
		Notes:          "Emitted on PATCH /me. Future: analytics.",
	},
	{
		EventType:      "ecom.user.soft_deleted.v1",
		ProducerModule: "internal/identity",
		ConsumerGroups: []string{},
		Status:         StatusActiveEmittedNoConsumer,
		Notes:          "Emitted on DELETE /me. Future: data erasure pipeline.",
	},
	{
		EventType:      "ecom.device.registered.v1",
		ProducerModule: "internal/identity",
		ConsumerGroups: []string{},
		Status:         StatusActiveEmittedNoConsumer,
		Notes:          "Emitted on POST /me/devices. Future: notification-device-sync.",
	},
	{
		EventType:      "ecom.device.revoked.v1",
		ProducerModule: "internal/identity",
		ConsumerGroups: []string{},
		Status:         StatusActiveEmittedNoConsumer,
		Notes:          "Emitted on device re-registration (old token revoked). Future: notification-device-sync.",
	},
}
