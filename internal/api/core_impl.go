package api

import (
	"context"
	"errors"

	"github.com/mopro/platform/internal/api/gen/core"
)

// CoreServer implements gencore.StrictServerInterface.
// All methods return 501 Not Implemented in Phase 4.0.
// Live handler migration happens in Phase 4.4+.
type CoreServer struct{}

var errNotImplemented = errors.New("not implemented")

func notImplemented501[R any]() (R, error) {
	var zero R
	return zero, errNotImplemented
}

// ── Health ─────────────────────────────────────────────────────────────────────

func (s *CoreServer) Healthz(_ context.Context, _ gencore.HealthzRequestObject) (gencore.HealthzResponseObject, error) {
	return gencore.Healthz200TextResponse("ok"), nil
}

// ── Address ────────────────────────────────────────────────────────────────────

func (s *CoreServer) ListAddresses(_ context.Context, _ gencore.ListAddressesRequestObject) (gencore.ListAddressesResponseObject, error) {
	return notImplemented501[gencore.ListAddressesResponseObject]()
}

func (s *CoreServer) CreateAddress(_ context.Context, _ gencore.CreateAddressRequestObject) (gencore.CreateAddressResponseObject, error) {
	return notImplemented501[gencore.CreateAddressResponseObject]()
}

func (s *CoreServer) DeleteAddress(_ context.Context, _ gencore.DeleteAddressRequestObject) (gencore.DeleteAddressResponseObject, error) {
	return notImplemented501[gencore.DeleteAddressResponseObject]()
}

func (s *CoreServer) UpdateAddress(_ context.Context, _ gencore.UpdateAddressRequestObject) (gencore.UpdateAddressResponseObject, error) {
	return notImplemented501[gencore.UpdateAddressResponseObject]()
}

// ── Auth ───────────────────────────────────────────────────────────────────────

func (s *CoreServer) Logout(_ context.Context, _ gencore.LogoutRequestObject) (gencore.LogoutResponseObject, error) {
	return notImplemented501[gencore.LogoutResponseObject]()
}

func (s *CoreServer) RequestOtp(_ context.Context, _ gencore.RequestOtpRequestObject) (gencore.RequestOtpResponseObject, error) {
	return notImplemented501[gencore.RequestOtpResponseObject]()
}

func (s *CoreServer) VerifyOtp(_ context.Context, _ gencore.VerifyOtpRequestObject) (gencore.VerifyOtpResponseObject, error) {
	return notImplemented501[gencore.VerifyOtpResponseObject]()
}

func (s *CoreServer) StepUp(_ context.Context, _ gencore.StepUpRequestObject) (gencore.StepUpResponseObject, error) {
	return notImplemented501[gencore.StepUpResponseObject]()
}

func (s *CoreServer) RefreshToken(_ context.Context, _ gencore.RefreshTokenRequestObject) (gencore.RefreshTokenResponseObject, error) {
	return notImplemented501[gencore.RefreshTokenResponseObject]()
}

// ── Discovery ──────────────────────────────────────────────────────────────────

func (s *CoreServer) ListBanners(_ context.Context, _ gencore.ListBannersRequestObject) (gencore.ListBannersResponseObject, error) {
	return notImplemented501[gencore.ListBannersResponseObject]()
}

func (s *CoreServer) ListRecommendations(_ context.Context, _ gencore.ListRecommendationsRequestObject) (gencore.ListRecommendationsResponseObject, error) {
	return notImplemented501[gencore.ListRecommendationsResponseObject]()
}

// ── Cart ───────────────────────────────────────────────────────────────────────

func (s *CoreServer) GetCart(_ context.Context, _ gencore.GetCartRequestObject) (gencore.GetCartResponseObject, error) {
	return notImplemented501[gencore.GetCartResponseObject]()
}

func (s *CoreServer) AddCartItem(_ context.Context, _ gencore.AddCartItemRequestObject) (gencore.AddCartItemResponseObject, error) {
	return notImplemented501[gencore.AddCartItemResponseObject]()
}

func (s *CoreServer) RemoveCartItem(_ context.Context, _ gencore.RemoveCartItemRequestObject) (gencore.RemoveCartItemResponseObject, error) {
	return notImplemented501[gencore.RemoveCartItemResponseObject]()
}

func (s *CoreServer) ReleaseCart(_ context.Context, _ gencore.ReleaseCartRequestObject) (gencore.ReleaseCartResponseObject, error) {
	return notImplemented501[gencore.ReleaseCartResponseObject]()
}

func (s *CoreServer) ReserveCart(_ context.Context, _ gencore.ReserveCartRequestObject) (gencore.ReserveCartResponseObject, error) {
	return notImplemented501[gencore.ReserveCartResponseObject]()
}

// ── Catalog ────────────────────────────────────────────────────────────────────

func (s *CoreServer) ListCategories(_ context.Context, _ gencore.ListCategoriesRequestObject) (gencore.ListCategoriesResponseObject, error) {
	return notImplemented501[gencore.ListCategoriesResponseObject]()
}

func (s *CoreServer) GetCategoryCommission(_ context.Context, _ gencore.GetCategoryCommissionRequestObject) (gencore.GetCategoryCommissionResponseObject, error) {
	return notImplemented501[gencore.GetCategoryCommissionResponseObject]()
}

func (s *CoreServer) ListProducts(_ context.Context, _ gencore.ListProductsRequestObject) (gencore.ListProductsResponseObject, error) {
	return notImplemented501[gencore.ListProductsResponseObject]()
}

func (s *CoreServer) CreateProduct(_ context.Context, _ gencore.CreateProductRequestObject) (gencore.CreateProductResponseObject, error) {
	return notImplemented501[gencore.CreateProductResponseObject]()
}

func (s *CoreServer) GetProduct(_ context.Context, _ gencore.GetProductRequestObject) (gencore.GetProductResponseObject, error) {
	return notImplemented501[gencore.GetProductResponseObject]()
}

// ── Search ─────────────────────────────────────────────────────────────────────

func (s *CoreServer) Search(_ context.Context, _ gencore.SearchRequestObject) (gencore.SearchResponseObject, error) {
	return notImplemented501[gencore.SearchResponseObject]()
}

func (s *CoreServer) SearchSuggest(_ context.Context, _ gencore.SearchSuggestRequestObject) (gencore.SearchSuggestResponseObject, error) {
	return notImplemented501[gencore.SearchSuggestResponseObject]()
}

func (s *CoreServer) SearchTrending(_ context.Context, _ gencore.SearchTrendingRequestObject) (gencore.SearchTrendingResponseObject, error) {
	return notImplemented501[gencore.SearchTrendingResponseObject]()
}

// ── Me ─────────────────────────────────────────────────────────────────────────

func (s *CoreServer) GetMe(_ context.Context, _ gencore.GetMeRequestObject) (gencore.GetMeResponseObject, error) {
	return notImplemented501[gencore.GetMeResponseObject]()
}

func (s *CoreServer) UpdateMe(_ context.Context, _ gencore.UpdateMeRequestObject) (gencore.UpdateMeResponseObject, error) {
	return notImplemented501[gencore.UpdateMeResponseObject]()
}

func (s *CoreServer) DeleteMe(_ context.Context, _ gencore.DeleteMeRequestObject) (gencore.DeleteMeResponseObject, error) {
	return notImplemented501[gencore.DeleteMeResponseObject]()
}

// ChangePassword is wired through the manual `POST /me/password` route in
// cmd/core-svc/auth_handlers.go (which can access identity.Service); the
// StrictServerInterface stub here exists only for the compile-time interface
// check and is never reached at runtime.
func (s *CoreServer) ChangePassword(_ context.Context, _ gencore.ChangePasswordRequestObject) (gencore.ChangePasswordResponseObject, error) {
	return notImplemented501[gencore.ChangePasswordResponseObject]()
}

func (s *CoreServer) RegisterDevice(_ context.Context, _ gencore.RegisterDeviceRequestObject) (gencore.RegisterDeviceResponseObject, error) {
	return notImplemented501[gencore.RegisterDeviceResponseObject]()
}

func (s *CoreServer) UnregisterDevice(_ context.Context, _ gencore.UnregisterDeviceRequestObject) (gencore.UnregisterDeviceResponseObject, error) {
	return notImplemented501[gencore.UnregisterDeviceResponseObject]()
}

// ── Orders ─────────────────────────────────────────────────────────────────────

func (s *CoreServer) ListOrders(_ context.Context, _ gencore.ListOrdersRequestObject) (gencore.ListOrdersResponseObject, error) {
	return notImplemented501[gencore.ListOrdersResponseObject]()
}

func (s *CoreServer) CreateOrder(_ context.Context, _ gencore.CreateOrderRequestObject) (gencore.CreateOrderResponseObject, error) {
	return notImplemented501[gencore.CreateOrderResponseObject]()
}

func (s *CoreServer) Checkout(_ context.Context, _ gencore.CheckoutRequestObject) (gencore.CheckoutResponseObject, error) {
	return notImplemented501[gencore.CheckoutResponseObject]()
}

func (s *CoreServer) GetOrder(_ context.Context, _ gencore.GetOrderRequestObject) (gencore.GetOrderResponseObject, error) {
	return notImplemented501[gencore.GetOrderResponseObject]()
}

func (s *CoreServer) CancelOrder(_ context.Context, _ gencore.CancelOrderRequestObject) (gencore.CancelOrderResponseObject, error) {
	return notImplemented501[gencore.CancelOrderResponseObject]()
}

func (s *CoreServer) RefundOrder(_ context.Context, _ gencore.RefundOrderRequestObject) (gencore.RefundOrderResponseObject, error) {
	return notImplemented501[gencore.RefundOrderResponseObject]()
}

func (s *CoreServer) ListReturns(_ context.Context, _ gencore.ListReturnsRequestObject) (gencore.ListReturnsResponseObject, error) {
	return notImplemented501[gencore.ListReturnsResponseObject]()
}

func (s *CoreServer) CreateReturn(_ context.Context, _ gencore.CreateReturnRequestObject) (gencore.CreateReturnResponseObject, error) {
	return notImplemented501[gencore.CreateReturnResponseObject]()
}

// ── Seller ─────────────────────────────────────────────────────────────────────

func (s *CoreServer) GetSellerOrderBreakdown(_ context.Context, _ gencore.GetSellerOrderBreakdownRequestObject) (gencore.GetSellerOrderBreakdownResponseObject, error) {
	return notImplemented501[gencore.GetSellerOrderBreakdownResponseObject]()
}

// compile-time interface check
var _ gencore.StrictServerInterface = (*CoreServer)(nil)
