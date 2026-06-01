package catalog

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
)

type fakeUGCRepo struct {
	insertErr    error
	createdQ     QuestionInput
	createdA     AnswerInput
	lastIsSeller bool
}

func (f *fakeUGCRepo) WithTx(ctx context.Context, fn func(pgx.Tx) error) error { return fn(nil) }
func (f *fakeUGCRepo) InsertReview(_ context.Context, in ReviewInput) (Review, error) {
	if f.insertErr != nil {
		return Review{}, f.insertErr
	}
	return Review{ID: 1, ProductID: in.ProductID, UserID: in.UserID, Rating: in.Rating, Body: in.Body, Status: "published"}, nil
}
func (f *fakeUGCRepo) InsertReviewRevision(context.Context, pgx.Tx, int64, int, string, string) error {
	return nil
}
func (f *fakeUGCRepo) UpdateReviewRow(_ context.Context, _ pgx.Tx, userID, reviewID int64, in ReviewInput) (Review, error) {
	return Review{ID: reviewID, UserID: userID, Rating: in.Rating, Body: in.Body}, nil
}
func (f *fakeUGCRepo) SoftDeleteReview(context.Context, int64, int64) error { return nil }
func (f *fakeUGCRepo) ListUserReviews(context.Context, int64, int, int) ([]UserReview, error) {
	return nil, nil
}
func (f *fakeUGCRepo) CountUserReviews(context.Context, int64) (int, error)      { return 0, nil }
func (f *fakeUGCRepo) UserReviewID(context.Context, int64, int64) (int64, error) { return 0, nil }
func (f *fakeUGCRepo) GetReviewForRevision(context.Context, int64) (Review, error) {
	return Review{}, nil
}
func (f *fakeUGCRepo) InsertQuestion(_ context.Context, in QuestionInput) (Question, error) {
	f.createdQ = in
	return Question{ID: 1, ProductID: in.ProductID, AuthorName: in.AuthorName, Body: in.Body}, nil
}
func (f *fakeUGCRepo) ListQuestions(context.Context, int64, QuestionSort, int, int) ([]Question, error) {
	return nil, nil
}
func (f *fakeUGCRepo) CountQuestions(context.Context, int64) (int, error) { return 0, nil }
func (f *fakeUGCRepo) GetQuestion(context.Context, int64) (Question, error) {
	return Question{ID: 1}, nil
}
func (f *fakeUGCRepo) ListAnswers(context.Context, int64) ([]Answer, error) { return nil, nil }
func (f *fakeUGCRepo) InsertAnswerAndRefresh(_ context.Context, in AnswerInput, isSeller bool) (Answer, error) {
	f.createdA = in
	f.lastIsSeller = isSeller
	return Answer{ID: 1, IsSeller: isSeller, Body: in.Body}, nil
}
func (f *fakeUGCRepo) ListUserQuestions(context.Context, int64, int, int) ([]Question, error) {
	return nil, nil
}
func (f *fakeUGCRepo) CountUserQuestions(context.Context, int64) (int, error) { return 0, nil }
func (f *fakeUGCRepo) ListSellerInboxQuestions(context.Context, []int64, bool, int, int) ([]Question, error) {
	return nil, nil
}
func (f *fakeUGCRepo) CountSellerInboxQuestions(context.Context, []int64, bool) (int, error) {
	return 0, nil
}

func TestCreateReview_Validation(t *testing.T) {
	s := NewUGCService(&fakeUGCRepo{})
	base := ReviewInput{ProductID: 1, UserID: 1, Rating: 4, Body: "ok"}
	mut := map[string]func(ReviewInput) ReviewInput{
		"rating 0":   func(i ReviewInput) ReviewInput { i.Rating = 0; return i },
		"rating 6":   func(i ReviewInput) ReviewInput { i.Rating = 6; return i },
		"empty body": func(i ReviewInput) ReviewInput { i.Body = ""; return i },
	}
	wants := map[string]error{"rating 0": ErrInvalidRating, "rating 6": ErrInvalidRating, "empty body": ErrEmptyBody}
	for name, m := range mut {
		if _, err := s.CreateReview(context.Background(), m(base)); !errors.Is(err, wants[name]) {
			t.Errorf("%s: got %v want %v", name, err, wants[name])
		}
	}
}

func TestCreateReview_ConflictPropagates(t *testing.T) {
	s := NewUGCService(&fakeUGCRepo{insertErr: ErrReviewExists})
	_, err := s.CreateReview(context.Background(), ReviewInput{ProductID: 1, UserID: 1, Rating: 5, Body: "x"})
	if !errors.Is(err, ErrReviewExists) {
		t.Errorf("want ErrReviewExists, got %v", err)
	}
}

func TestCreateAnswer_IsSellerFalse(t *testing.T) {
	repo := &fakeUGCRepo{}
	s := NewUGCService(repo)
	a, err := s.CreateAnswer(context.Background(), AnswerInput{QuestionID: 1, UserID: 2, Body: "answer"})
	if err != nil {
		t.Fatal(err)
	}
	if a.IsSeller || repo.lastIsSeller {
		t.Error("is_seller defaults false at the service layer (handler computes it from the seller binding)")
	}
}

func TestQAValidation(t *testing.T) {
	s := NewUGCService(&fakeUGCRepo{})
	if _, err := s.CreateQuestion(context.Background(), QuestionInput{Body: ""}); !errors.Is(err, ErrEmptyBody) {
		t.Errorf("empty question: %v", err)
	}
	if _, err := s.CreateAnswer(context.Background(), AnswerInput{Body: ""}); !errors.Is(err, ErrEmptyBody) {
		t.Errorf("empty answer: %v", err)
	}
}

func TestListSellerQuestions_EmptyProductsShortCircuits(t *testing.T) {
	svc := NewUGCService(&fakeUGCRepo{})
	items, total, err := svc.ListSellerQuestions(context.Background(), nil, false, 20, 0)
	if err != nil {
		t.Fatalf("ListSellerQuestions: %v", err)
	}
	if len(items) != 0 || total != 0 {
		t.Errorf("want empty/0, got len=%d total=%d", len(items), total)
	}
}
