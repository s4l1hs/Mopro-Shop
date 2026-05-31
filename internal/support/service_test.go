package support

import (
	"context"
	"errors"
	"testing"
)

type fakeRepo struct {
	inserted TicketInput
	stored   map[int64]Ticket
}

func (f *fakeRepo) Insert(_ context.Context, in TicketInput) (Ticket, error) {
	f.inserted = in
	return Ticket{ID: 1, UserID: in.UserID, Email: in.Email, Subject: in.Subject,
		Body: in.Body, Category: in.Category, Status: "open"}, nil
}
func (f *fakeRepo) ListByUser(_ context.Context, userID int64, _, _ int) ([]Ticket, error) {
	var out []Ticket
	for _, t := range f.stored {
		if t.UserID == userID {
			out = append(out, t)
		}
	}
	return out, nil
}
func (f *fakeRepo) GetByID(_ context.Context, id int64) (Ticket, error) {
	if t, ok := f.stored[id]; ok {
		return t, nil
	}
	return Ticket{}, ErrTicketNotFound
}

func valid() TicketInput {
	return TicketInput{Email: "a@b.co", Subject: "Hi", Body: "Need help", Category: "other"}
}

func TestCreate_GuestVsAuthed(t *testing.T) {
	repo := &fakeRepo{}
	s := NewService(repo)

	// Guest: UserID 0.
	if _, err := s.CreateTicket(context.Background(), valid()); err != nil {
		t.Fatal(err)
	}
	if repo.inserted.UserID != 0 {
		t.Errorf("guest UserID should be 0, got %d", repo.inserted.UserID)
	}

	// Authed: UserID populated.
	in := valid()
	in.UserID = 42
	if _, err := s.CreateTicket(context.Background(), in); err != nil {
		t.Fatal(err)
	}
	if repo.inserted.UserID != 42 {
		t.Errorf("authed UserID should be 42, got %d", repo.inserted.UserID)
	}
}

func TestCreate_Validation(t *testing.T) {
	s := NewService(&fakeRepo{})
	cases := []struct {
		name string
		mut  func(*TicketInput)
		want error
	}{
		{"bad email", func(i *TicketInput) { i.Email = "nope" }, ErrInvalidEmail},
		{"empty subject", func(i *TicketInput) { i.Subject = "  " }, ErrEmptySubject},
		{"subject too long", func(i *TicketInput) { i.Subject = string(make([]byte, 101)) }, ErrSubjectTooLong},
		{"empty body", func(i *TicketInput) { i.Body = "" }, ErrEmptyBody},
		{"body too long", func(i *TicketInput) { i.Body = string(make([]byte, 2001)) }, ErrBodyTooLong},
		{"bad category", func(i *TicketInput) { i.Category = "spaceship" }, ErrInvalidCategory},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			in := valid()
			// Fill long-string cases with real chars (make([]byte) is NUL → spaces trim).
			tc.mut(&in)
			if tc.name == "subject too long" {
				in.Subject = repeat('x', 101)
			}
			if tc.name == "body too long" {
				in.Body = repeat('x', 2001)
			}
			if _, err := s.CreateTicket(context.Background(), in); !errors.Is(err, tc.want) {
				t.Errorf("got %v want %v", err, tc.want)
			}
		})
	}
}

func TestGetTicket_OwnershipScoped(t *testing.T) {
	repo := &fakeRepo{stored: map[int64]Ticket{7: {ID: 7, UserID: 1}}}
	s := NewService(repo)
	if _, err := s.GetTicket(context.Background(), 1, 7); err != nil {
		t.Errorf("owner should read own ticket: %v", err)
	}
	if _, err := s.GetTicket(context.Background(), 2, 7); !errors.Is(err, ErrTicketNotFound) {
		t.Errorf("non-owner must get NotFound, got %v", err)
	}
}

func repeat(c byte, n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = c
	}
	return string(b)
}
