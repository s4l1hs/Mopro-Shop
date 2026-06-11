package refund

import (
	"context"
	"fmt"
	"log/slog"
	"strconv"

	"github.com/mopro/platform/internal/ledger"
)

// equityAcctType is the counter-equity debited per refund settlement (migration
// 0082). The currency suffix (the coin code) is supplied at lookup time.
const equityAcctType = "equity:refund_distribution"

type service struct {
	wallet Wallet
	// coinCurrency is the coin code refunds are minted in (e.g. TRY_COIN), from
	// DEFAULT_CASHBACK_CURRENCY. The refund amount is the order's fiat charge,
	// credited 1:1 as coin (launch peg "1 Coin ≈ 1 TL").
	coinCurrency string
	log          *slog.Logger
}

// NewService builds the refund settlement Service. w is wallet.Service.
func NewService(w Wallet, coinCurrency string, log *slog.Logger) Service {
	if log == nil {
		log = slog.Default()
	}
	return &service{wallet: w, coinCurrency: coinCurrency, log: log}
}

func (s *service) SettleRefund(ctx context.Context, ev RefundEvent) error {
	if ev.RefundAmountMinor <= 0 {
		// Nothing to credit (e.g. a zero-amount return). Ack so it doesn't redeliver.
		s.log.WarnContext(ctx, "refund: zero amount, skipping",
			"return_id", ev.ReturnID, "order_id", ev.OrderID)
		return nil
	}

	equityAcctID, err := s.wallet.FindAccount(ctx, equityAcctType, s.coinCurrency)
	if err != nil {
		return fmt.Errorf("refund: find equity account %s/%s: %w", equityAcctType, s.coinCurrency, err)
	}
	userAcctID, err := s.wallet.OpenOrFindUserWallet(ctx, ev.UserID, s.coinCurrency)
	if err != nil {
		return fmt.Errorf("refund: open user wallet user=%d/%s: %w", ev.UserID, s.coinCurrency, err)
	}

	// D equity:refund_distribution ↔ C user wallet, single-currency (coin), balanced.
	// Idempotent: refund:<return_id> is UNIQUE on transactions; a replay returns the
	// original txn id without a second post (wallet.Service layer-3 idempotency).
	_, err = s.wallet.Post(ctx, ledger.PostInput{
		Type:           "refund_settlement",
		Reference:      fmt.Sprintf("return:%d", ev.ReturnID),
		IdempotencyKey: fmt.Sprintf("refund:%d", ev.ReturnID),
		Market:         ev.Market,
		Currency:       s.coinCurrency,
		EventType:      "fin.refund.coin.credited.v1",
		Metadata: map[string]string{
			"return_id": strconv.FormatInt(ev.ReturnID, 10),
			"order_id":  strconv.FormatInt(ev.OrderID, 10),
			"user_id":   strconv.FormatInt(ev.UserID, 10),
		},
		Entries: []ledger.Entry{
			{AccountID: equityAcctID, Direction: ledger.Debit, AmountMinor: ev.RefundAmountMinor},
			{AccountID: userAcctID, Direction: ledger.Credit, AmountMinor: ev.RefundAmountMinor},
		},
	})
	if err != nil {
		return fmt.Errorf("refund: post coin credit return=%d: %w", ev.ReturnID, err)
	}
	s.log.InfoContext(ctx, "refund: coin credited",
		"return_id", ev.ReturnID, "user_id", ev.UserID,
		"amount_minor", ev.RefundAmountMinor, "currency", s.coinCurrency)
	return nil
}
