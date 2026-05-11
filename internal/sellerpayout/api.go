// Package sellerpayout owns the seller net payout engine: scheduling, unlock, and daily cron (fin-svc).
// unlock_at = delivered_at + 3 business days via pkg/timex.AddBusinessDays.
// Net = gross - commission - KDV; all amounts frozen at order completion.
package sellerpayout

// Service defines the public interface of the seller payout engine.
type Service interface{}

// Repository defines the storage interface of the seller payout engine.
type Repository interface{}
