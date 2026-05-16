package ledger

import "errors"

// ErrDuplicateIdempotency is returned by walletRepository.InsertTransaction when the
// UNIQUE constraint on transactions.idempotency_key fires (pgError 23505).
// The wallet service intercepts this and returns the original txnID to the caller
// as an idempotent success — callers of wallet.Post / wallet.PostInTx never see it.
var ErrDuplicateIdempotency = errors.New("ledger: duplicate idempotency_key")
