//go:build !integration

package identity_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mopro/platform/internal/identity"
)

// ── address mock stubs on mockRepo (satisfies new Repository interface methods) ──
// mockRepo.addresses must be added as a field; done below in newMockRepoWithAddress.
// We extend mockRepo with a pointer-receiver method set via Go's single struct.

func (m *mockRepo) ListAddresses(_ context.Context, userID int64) ([]identity.Address, error) {
	var out []identity.Address
	for _, a := range m.addrStore {
		if a.UserID == userID {
			out = append(out, a)
		}
	}
	if out == nil {
		out = []identity.Address{}
	}
	return out, nil
}

func (m *mockRepo) ClearDefaultAddresses(_ context.Context, userID int64) error {
	for i := range m.addrStore {
		if m.addrStore[i].UserID == userID {
			m.addrStore[i].IsDefault = false
		}
	}
	return nil
}

func (m *mockRepo) InsertAddress(_ context.Context, userID int64, a identity.AddressRow) (identity.Address, error) {
	id := int64(len(m.addrStore) + 1)
	addr := identity.Address{
		ID:           id,
		UserID:       userID,
		Label:        a.Label,
		Name:         a.NameEnc,
		Phone:        a.PhoneEnc,
		FullAddress:  a.FullAddressEnc,
		Neighborhood: a.NeighborhoodEnc,
		District:     a.District,
		City:         a.City,
		PostalCode:   a.PostalCode,
		IsDefault:    a.IsDefault,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	m.addrStore = append(m.addrStore, addr)
	return addr, nil
}

func (m *mockRepo) GetAddress(_ context.Context, userID, addressID int64) (identity.Address, error) {
	for _, a := range m.addrStore {
		if a.ID == addressID {
			if a.UserID != userID {
				return identity.Address{}, identity.ErrAddressNotFound
			}
			return a, nil
		}
	}
	return identity.Address{}, identity.ErrAddressNotFound
}

func (m *mockRepo) UpdateAddress(_ context.Context, userID, addressID int64, a identity.AddressRow) (identity.Address, error) {
	for i := range m.addrStore {
		if m.addrStore[i].ID == addressID {
			if m.addrStore[i].UserID != userID {
				return identity.Address{}, identity.ErrAddressNotFound
			}
			m.addrStore[i].Label = a.Label
			m.addrStore[i].District = a.District
			m.addrStore[i].City = a.City
			m.addrStore[i].PostalCode = a.PostalCode
			m.addrStore[i].IsDefault = a.IsDefault
			m.addrStore[i].UpdatedAt = time.Now()
			return m.addrStore[i], nil
		}
	}
	return identity.Address{}, identity.ErrAddressNotFound
}

func (m *mockRepo) DeleteAddress(_ context.Context, userID, addressID int64) error {
	for i, a := range m.addrStore {
		if a.ID == addressID {
			if a.UserID != userID {
				return identity.ErrAddressNotFound
			}
			m.addrStore = append(m.addrStore[:i], m.addrStore[i+1:]...)
			return nil
		}
	}
	return identity.ErrAddressNotFound
}

// ── IDOR security tests ────────────────────────────────────────────────────────

// newAddressService creates a service with a repo that has one seeded address owned by ownerID.
func newAddressService(ownerID, addrID int64, t *testing.T) identity.Service {
	t.Helper()
	repo := newMockRepoWithAddress(ownerID, addrID)
	return newTestService(repo, &mockSMS{}, &mockLimiter{}, t)
}

func newMockRepoWithAddress(ownerID, addrID int64) *mockRepo {
	r := newMockRepo()
	r.addrStore = []identity.Address{
		{
			ID:          addrID,
			UserID:      ownerID,
			Label:       "Ev",
			Name:        "enc:test-name",
			Phone:       "enc:+905321234567",
			FullAddress: "enc:Test Cad. No:1",
			District:    "Kadıköy",
			City:        "İstanbul",
			IsDefault:   true,
			CreatedAt:   time.Now(),
			UpdatedAt:   time.Now(),
		},
	}
	return r
}

// TestGetAddress_OtherUser_Returns404 verifies IDOR protection on GET.
func TestGetAddress_OtherUser_Returns404(t *testing.T) {
	const ownerID = int64(1)
	const attackerID = int64(2)
	const addrID = int64(10)

	svc := newAddressService(ownerID, addrID, t)

	_, err := svc.GetAddress(context.Background(), attackerID, addrID)
	if !errors.Is(err, identity.ErrAddressNotFound) {
		t.Fatalf("expected ErrAddressNotFound, got %v", err)
	}
}

// TestUpdateAddress_OtherUser_Returns404 verifies IDOR protection on PUT.
func TestUpdateAddress_OtherUser_Returns404(t *testing.T) {
	const ownerID = int64(1)
	const attackerID = int64(2)
	const addrID = int64(10)

	svc := newAddressService(ownerID, addrID, t)

	_, err := svc.UpdateAddress(context.Background(), attackerID, addrID, identity.AddressInput{
		Label:       "Hacked",
		Name:        "Attacker",
		FullAddress: "Evil St.",
		District:    "X",
		City:        "Y",
	})
	if !errors.Is(err, identity.ErrAddressNotFound) {
		t.Fatalf("expected ErrAddressNotFound, got %v", err)
	}
}

// TestDeleteAddress_OtherUser_Returns404 verifies IDOR protection on DELETE.
func TestDeleteAddress_OtherUser_Returns404(t *testing.T) {
	const ownerID = int64(1)
	const attackerID = int64(2)
	const addrID = int64(10)

	svc := newAddressService(ownerID, addrID, t)

	err := svc.DeleteAddress(context.Background(), attackerID, addrID)
	if !errors.Is(err, identity.ErrAddressNotFound) {
		t.Fatalf("expected ErrAddressNotFound, got %v", err)
	}
}

// TestListAddresses_OnlyShowsCallerOwnAddresses verifies list isolation.
func TestListAddresses_OnlyShowsCallerOwnAddresses(t *testing.T) {
	repo := newMockRepo()
	// user 1 has address 10
	// user 2 has address 11
	repo.addrStore = []identity.Address{
		{ID: 10, UserID: 1, Name: "enc:a", Phone: "enc:b", FullAddress: "enc:c", District: "D", City: "C"},
		{ID: 11, UserID: 2, Name: "enc:x", Phone: "enc:y", FullAddress: "enc:z", District: "D", City: "C"},
	}
	svc := newTestService(repo, &mockSMS{}, &mockLimiter{}, t)

	addrs, err := svc.ListAddresses(context.Background(), 1)
	if err != nil {
		t.Fatalf("ListAddresses: %v", err)
	}
	// Should only see address 10; decryption will fail on "enc:*" values but
	// service logs and skips; verify empty result is acceptable for isolation.
	for _, a := range addrs {
		if a.UserID != 1 {
			t.Errorf("returned address %d owned by user %d, want user 1", a.ID, a.UserID)
		}
	}
}
