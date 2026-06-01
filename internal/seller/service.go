package seller

import "context"

type service struct{ repo Repository }

// NewService builds the seller module service.
func NewService(repo Repository) Service { return &service{repo: repo} }

func (s *service) GetBySlug(ctx context.Context, slug string) (Seller, error) {
	return s.repo.GetBySlug(ctx, slug)
}

func (s *service) GetByID(ctx context.Context, id int64) (Seller, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *service) ResolveSellerForUser(ctx context.Context, userID int64) (int64, bool, error) {
	return s.repo.SellerIDForUser(ctx, userID)
}

func (s *service) GetBindingForUser(ctx context.Context, userID int64) (Binding, bool, error) {
	return s.repo.BindingForUser(ctx, userID)
}
