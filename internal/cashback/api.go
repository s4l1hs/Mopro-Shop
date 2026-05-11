// Package cashback owns the perpetual cashback engine: plan creation, freezing, and monthly payments (fin-svc).
// v6 LOCKED PERPETUAL MODEL: monthly_coin = (commission_minor × ref_rate_bps) / 10000 / 12
// Reference interest rate is frozen at 5000 bps (50%) per plan at creation; NEVER changed for existing plans.
package cashback

// Service defines the public interface of the cashback engine.
type Service interface{}

// Repository defines the storage interface of the cashback engine.
type Repository interface{}
