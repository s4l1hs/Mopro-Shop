package main

import (
	"context"

	"github.com/mopro/platform/internal/identity"
	"github.com/mopro/platform/internal/order"
)

// identityAddressResolver adapts identity.Service to order.AddressResolver (OR-02),
// keeping internal/order decoupled from internal/identity. It resolves the user's
// saved (decrypted) address via the in-process identity Service (§3.1) and copies it
// into a frozen order.OrderAddress snapshot; the order repo re-encrypts the PII fields
// at rest.
//
// get is a getter rather than a direct reference because identitySvc is constructed
// after orderSvc in main.go; the resolver is only ever invoked at request time (during
// checkout), by which point identitySvc is wired.
type identityAddressResolver struct {
	get func() identity.Service
}

func (a identityAddressResolver) ResolveDeliveryAddress(ctx context.Context, userID, addressID int64) (order.OrderAddress, error) {
	addr, err := a.get().GetAddress(ctx, userID, addressID)
	if err != nil {
		return order.OrderAddress{}, err
	}
	return order.OrderAddress{
		Label:         addr.Label,
		RecipientName: addr.Name,
		Phone:         addr.Phone,
		FullAddress:   addr.FullAddress,
		Neighborhood:  addr.Neighborhood,
		District:      addr.District,
		City:          addr.City,
		PostalCode:    addr.PostalCode,
	}, nil
}
