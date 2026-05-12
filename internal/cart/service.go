package cart

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/mopro/platform/internal/catalog"
)

const reservationTTLSec = int64(15 * 60) // 15 minutes

type cartService struct {
	repo    Repository
	catalog catalog.Service
}

// NewService constructs a cart Service wired to a Repository and the catalog Service.
// catalogSvc is used to validate variant existence on AddItem.
func NewService(repo Repository, catalogSvc catalog.Service) Service {
	return &cartService{repo: repo, catalog: catalogSvc}
}

func (s *cartService) AddItem(ctx context.Context, userID, variantID int64, qty int) error {
	if _, err := s.catalog.GetVariantByID(ctx, variantID); err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			return ErrVariantNotFound
		}
		return fmt.Errorf("cart: AddItem validate variant: %w", err)
	}
	return s.repo.SetItem(ctx, userID, variantID, qty)
}

func (s *cartService) RemoveItem(ctx context.Context, userID, variantID int64) error {
	return s.repo.RemoveItem(ctx, userID, variantID)
}

func (s *cartService) GetCart(ctx context.Context, userID int64) (Cart, error) {
	items, err := s.repo.GetItems(ctx, userID)
	if err != nil {
		return Cart{}, fmt.Errorf("cart: GetCart: %w", err)
	}
	if items == nil {
		items = []CartItem{}
	}
	return Cart{UserID: userID, Items: items}, nil
}

func (s *cartService) Reserve(ctx context.Context, userID int64) (string, time.Time, error) {
	items, err := s.repo.GetItems(ctx, userID)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("cart: Reserve get items: %w", err)
	}
	if len(items) == 0 {
		return "", time.Time{}, ErrCartEmpty
	}

	reservationID, err := newReservationID()
	if err != nil {
		return "", time.Time{}, fmt.Errorf("cart: Reserve generate ID: %w", err)
	}

	expiresAt := time.Now().Add(time.Duration(reservationTTLSec) * time.Second)

	// Saga: track which items reserved so we can compensate on partial failure.
	var reserved []CartItem
	for _, item := range items {
		ok, _, tryErr := s.repo.TryReserve(ctx, item.VariantID, item.Qty, reservationID, userID, reservationTTLSec)
		if tryErr != nil {
			_ = s.releasePartial(ctx, reservationID, reserved)
			return "", time.Time{}, fmt.Errorf("cart: Reserve TryReserve: %w", tryErr)
		}
		if !ok {
			_ = s.releasePartial(ctx, reservationID, reserved)
			return "", time.Time{}, ErrOutOfStock
		}
		reserved = append(reserved, item)
	}

	// Persist manifest so Release can restore stock.
	if err := s.repo.SetManifest(ctx, reservationID, reserved, reservationTTLSec); err != nil {
		_ = s.releasePartial(ctx, reservationID, reserved)
		return "", time.Time{}, fmt.Errorf("cart: Reserve set manifest: %w", err)
	}

	return reservationID, expiresAt, nil
}

// releasePartial undoes TryReserve calls that succeeded before a saga failure.
func (s *cartService) releasePartial(ctx context.Context, reservationID string, reserved []CartItem) error {
	if len(reserved) == 0 {
		return nil
	}
	// Write manifest so ReleaseReservation can find the items.
	if err := s.repo.SetManifest(ctx, reservationID, reserved, reservationTTLSec); err != nil {
		return err
	}
	return s.repo.ReleaseReservation(ctx, reservationID)
}

func (s *cartService) Release(ctx context.Context, reservationID string) error {
	return s.repo.ReleaseReservation(ctx, reservationID)
}

func (s *cartService) SeedStock(ctx context.Context, variantID int64, stock int) error {
	return s.repo.SeedStock(ctx, variantID, stock)
}

func newReservationID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
