// Package support owns customer support tickets in support_schema. Ticket
// creation is open to guests; listing/detail are auth-scoped to the owner.
// (Public help/FAQ content lives in the separate internal/help module.)
package support

import (
	"context"
	"errors"
	"net/mail"
	"strings"
	"time"
)

const (
	maxSubject  = 100
	maxBody     = 2000
	maxPageSize = 50
)

var (
	ErrInvalidEmail    = errors.New("support: invalid email")
	ErrEmptySubject    = errors.New("support: subject required")
	ErrSubjectTooLong  = errors.New("support: subject too long")
	ErrEmptyBody       = errors.New("support: body required")
	ErrBodyTooLong     = errors.New("support: body too long")
	ErrInvalidCategory = errors.New("support: invalid category")
	ErrTicketNotFound  = errors.New("support: ticket not found")
)

var validCategories = map[string]bool{
	"order_issue": true, "payment": true, "returns": true, "account": true, "other": true,
}

// Ticket is a support ticket. UserID is 0 for guest submissions.
type Ticket struct {
	ID                 int64     `json:"id"`
	UserID             int64     `json:"user_id,omitempty"`
	Email              string    `json:"email"`
	Subject            string    `json:"subject"`
	Body               string    `json:"body"`
	Category           string    `json:"category"`
	RelatedOrderID     int64     `json:"related_order_id,omitempty"`
	RelatedArticleSlug string    `json:"related_article_slug,omitempty"`
	Status             string    `json:"status"`
	CreatedAt          time.Time `json:"created_at"`
}

// TicketInput is the validated create payload. UserID 0 = guest.
type TicketInput struct {
	UserID             int64
	Email              string
	Subject            string
	Body               string
	Category           string
	RelatedOrderID     int64
	RelatedArticleSlug string
}

func (in TicketInput) validate() error {
	if _, err := mail.ParseAddress(in.Email); err != nil {
		return ErrInvalidEmail
	}
	subj := strings.TrimSpace(in.Subject)
	switch {
	case subj == "":
		return ErrEmptySubject
	case len(subj) > maxSubject:
		return ErrSubjectTooLong
	}
	body := strings.TrimSpace(in.Body)
	switch {
	case body == "":
		return ErrEmptyBody
	case len(body) > maxBody:
		return ErrBodyTooLong
	}
	if !validCategories[in.Category] {
		return ErrInvalidCategory
	}
	return nil
}

// Service is the public surface of the support module.
type Service interface {
	CreateTicket(ctx context.Context, in TicketInput) (Ticket, error)
	ListTickets(ctx context.Context, userID int64, page, pageSize int) ([]Ticket, error)
	GetTicket(ctx context.Context, userID, id int64) (Ticket, error)
}

// Repository is the storage interface used only by service.go.
type Repository interface {
	Insert(ctx context.Context, in TicketInput) (Ticket, error)
	ListByUser(ctx context.Context, userID int64, limit, offset int) ([]Ticket, error)
	GetByID(ctx context.Context, id int64) (Ticket, error)
}
