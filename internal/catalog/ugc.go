package catalog

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Tranche 3 — reviews write-side + Q&A. Kept in separate interfaces from the
// (mocked) catalog.Service so adding write methods doesn't churn its stubs.

const (
	ReviewWindowDays = 90
	maxReviewBody    = 2000
	maxReviewTitle   = 100
	maxQuestionBody  = 500
	maxAnswerBody    = 1000
)

var (
	ErrReviewExists     = errors.New("catalog: review already exists for product")
	ErrInvalidRating    = errors.New("catalog: rating must be 1-5")
	ErrEmptyBody        = errors.New("catalog: body required")
	ErrBodyTooLong      = errors.New("catalog: body too long")
	ErrTitleTooLong     = errors.New("catalog: title too long")
	ErrQuestionNotFound = errors.New("catalog: question not found")
)

// ── Reviews write-side ────────────────────────────────────────────────────────

type ReviewInput struct {
	ProductID       int64
	UserID          int64
	Rating          int
	Title           string
	Body            string
	SubmittedLocale string
}

type Review struct {
	ID        int64     `json:"id"`
	ProductID int64     `json:"product_id"`
	UserID    int64     `json:"user_id"`
	Rating    int       `json:"rating"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// UserReview is a Review enriched with product display info for /me/reviews.
type UserReview struct {
	Review
	ProductTitle     string `json:"product_title"`
	ProductSlug      string `json:"product_slug"`
	ProductThumbnail string `json:"product_thumbnail"`
}

// ReviewEligibility is the server-computed review block for a (user, product).
type ReviewEligibility struct {
	CanReview        bool       `json:"canReview"`
	ReviewableUntil  *time.Time `json:"reviewableUntil,omitempty"`
	ExistingReviewID int64      `json:"existingReviewId,omitempty"`
}

type ReviewWriteService interface {
	// CreateReview returns ErrReviewExists when the (product_id, user_id) row
	// already exists (the caller fetches the existing id via UserReviewID).
	CreateReview(ctx context.Context, in ReviewInput) (Review, error)
	UpdateReview(ctx context.Context, userID, reviewID int64, in ReviewInput) (Review, error)
	DeleteReview(ctx context.Context, userID, reviewID int64) error
	ListUserReviews(ctx context.Context, userID int64, limit, offset int) ([]UserReview, int, error)
	// UserReviewID returns the user's review id for a product, or 0 if none.
	UserReviewID(ctx context.Context, userID, productID int64) (int64, error)
}

func (in ReviewInput) validate() error {
	if in.Rating < 1 || in.Rating > 5 {
		return ErrInvalidRating
	}
	if len(in.Body) == 0 {
		return ErrEmptyBody
	}
	if len(in.Body) > maxReviewBody {
		return ErrBodyTooLong
	}
	if len(in.Title) > maxReviewTitle {
		return ErrTitleTooLong
	}
	return nil
}

// ── Q&A ─────────────────────────────────────────────────────────────────────

type QuestionSort string

const (
	QuestionSortNewest       QuestionSort = "newest"
	QuestionSortMostAnswered QuestionSort = "most_answered"
)

func ParseQuestionSort(s string) QuestionSort {
	if QuestionSort(s) == QuestionSortMostAnswered {
		return QuestionSortMostAnswered
	}
	return QuestionSortNewest
}

type Question struct {
	ID          int64     `json:"id"`
	ProductID   int64     `json:"product_id"`
	UserID      int64     `json:"user_id"`
	AuthorName  string    `json:"author_name"`
	Body        string    `json:"body"`
	AnswerCount int       `json:"answer_count"`
	CreatedAt   time.Time `json:"created_at"`
}

type Answer struct {
	ID         int64     `json:"id"`
	QuestionID int64     `json:"question_id"`
	UserID     int64     `json:"user_id"`
	AuthorName string    `json:"author_name"`
	IsSeller   bool      `json:"is_seller"`
	Body       string    `json:"body"`
	CreatedAt  time.Time `json:"created_at"`
}

type QuestionInput struct {
	ProductID       int64
	UserID          int64
	AuthorName      string
	Body            string
	SubmittedLocale string
}

type AnswerInput struct {
	QuestionID      int64
	UserID          int64
	AuthorName      string
	Body            string
	SubmittedLocale string
	// IsSeller is set by the handler when the answering user owns the product
	// (Tranche 5a). Drives the "Satıcı" badge.
	IsSeller bool
}

type QAService interface {
	CreateQuestion(ctx context.Context, in QuestionInput) (Question, error)
	ListQuestions(ctx context.Context, productID int64, sort QuestionSort, limit, offset int) ([]Question, int, error)
	GetQuestion(ctx context.Context, questionID int64) (Question, []Answer, error)
	CreateAnswer(ctx context.Context, in AnswerInput) (Answer, error)
	ListUserQuestions(ctx context.Context, userID int64, limit, offset int) ([]Question, int, error)
	// ListSellerQuestions is the seller Q&A inbox: questions on the given
	// (seller-owned) products; onlyUnanswered filters to those without a seller answer.
	ListSellerQuestions(ctx context.Context, productIDs []int64, onlyUnanswered bool, limit, offset int) ([]Question, int, error)
}

// UGCRepository backs both the review write-side and Q&A.
type UGCRepository interface {
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
	// Reviews
	InsertReview(ctx context.Context, in ReviewInput) (Review, error) // ErrReviewExists on 23505
	InsertReviewRevision(ctx context.Context, tx pgx.Tx, reviewID int64, rating int, title, body string) error
	UpdateReviewRow(ctx context.Context, tx pgx.Tx, userID, reviewID int64, in ReviewInput) (Review, error)
	SoftDeleteReview(ctx context.Context, userID, reviewID int64) error
	ListUserReviews(ctx context.Context, userID int64, limit, offset int) ([]UserReview, error)
	CountUserReviews(ctx context.Context, userID int64) (int, error)
	UserReviewID(ctx context.Context, userID, productID int64) (int64, error)
	GetReviewForRevision(ctx context.Context, reviewID int64) (Review, error)
	// Q&A
	InsertQuestion(ctx context.Context, in QuestionInput) (Question, error)
	ListQuestions(ctx context.Context, productID int64, sort QuestionSort, limit, offset int) ([]Question, error)
	CountQuestions(ctx context.Context, productID int64) (int, error)
	GetQuestion(ctx context.Context, questionID int64) (Question, error)
	ListAnswers(ctx context.Context, questionID int64) ([]Answer, error)
	InsertAnswerAndRefresh(ctx context.Context, in AnswerInput, isSeller bool) (Answer, error)
	ListUserQuestions(ctx context.Context, userID int64, limit, offset int) ([]Question, error)
	CountUserQuestions(ctx context.Context, userID int64) (int, error)
	ListSellerInboxQuestions(ctx context.Context, productIDs []int64, onlyUnanswered bool, limit, offset int) ([]Question, error)
	CountSellerInboxQuestions(ctx context.Context, productIDs []int64, onlyUnanswered bool) (int, error)
}
