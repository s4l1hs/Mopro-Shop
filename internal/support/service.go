package support

import "context"

type service struct {
	repo Repository
}

// NewService builds the support Service.
func NewService(repo Repository) Service { return &service{repo: repo} }

func (s *service) CreateTicket(ctx context.Context, in TicketInput) (Ticket, error) {
	if err := in.validate(); err != nil {
		return Ticket{}, err
	}
	return s.repo.Insert(ctx, in)
}

func (s *service) ListTickets(ctx context.Context, userID int64, page, pageSize int) ([]Ticket, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > maxPageSize {
		pageSize = 20
	}
	return s.repo.ListByUser(ctx, userID, pageSize, (page-1)*pageSize)
}

// GetTicket is ownership-scoped: a user can only read their own ticket.
func (s *service) GetTicket(ctx context.Context, userID, id int64) (Ticket, error) {
	t, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return Ticket{}, err
	}
	if t.UserID != userID {
		return Ticket{}, ErrTicketNotFound
	}
	return t, nil
}
