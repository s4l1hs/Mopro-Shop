package catalog

import (
	"context"

	"github.com/jackc/pgx/v5"
)

const ugcMaxPageSize = 50

type ugcService struct {
	repo UGCRepository
}

// NewUGCService builds the combined review-write + Q&A service.
func NewUGCService(repo UGCRepository) *ugcService { return &ugcService{repo: repo} }

func clampPage(limit, offset int) (int, int) {
	if limit < 1 || limit > ugcMaxPageSize {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}
	return limit, offset
}

// ── ReviewWriteService ────────────────────────────────────────────────────────

func (s *ugcService) CreateReview(ctx context.Context, in ReviewInput) (Review, error) {
	if err := in.validate(); err != nil {
		return Review{}, err
	}
	// InsertReview writes the row + its initial revision atomically; returns
	// ErrReviewExists on the (product_id, user_id) unique conflict.
	return s.repo.InsertReview(ctx, in)
}

func (s *ugcService) UpdateReview(ctx context.Context, userID, reviewID int64, in ReviewInput) (Review, error) {
	if err := in.validate(); err != nil {
		return Review{}, err
	}
	var out Review
	err := s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		rec, e := s.repo.UpdateReviewRow(ctx, tx, userID, reviewID, in)
		if e != nil {
			return e
		}
		if e := s.repo.InsertReviewRevision(ctx, tx, reviewID, in.Rating, in.Title, in.Body); e != nil {
			return e
		}
		out = rec
		return nil
	})
	return out, err
}

func (s *ugcService) DeleteReview(ctx context.Context, userID, reviewID int64) error {
	return s.repo.SoftDeleteReview(ctx, userID, reviewID)
}

func (s *ugcService) ListUserReviews(ctx context.Context, userID int64, limit, offset int) ([]UserReview, int, error) {
	limit, offset = clampPage(limit, offset)
	items, err := s.repo.ListUserReviews(ctx, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	total, err := s.repo.CountUserReviews(ctx, userID)
	if err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func (s *ugcService) UserReviewID(ctx context.Context, userID, productID int64) (int64, error) {
	return s.repo.UserReviewID(ctx, userID, productID)
}

// ── QAService ─────────────────────────────────────────────────────────────────

func (s *ugcService) CreateQuestion(ctx context.Context, in QuestionInput) (Question, error) {
	body := in.Body
	if len(body) == 0 {
		return Question{}, ErrEmptyBody
	}
	if len(body) > maxQuestionBody {
		return Question{}, ErrBodyTooLong
	}
	return s.repo.InsertQuestion(ctx, in)
}

func (s *ugcService) ListQuestions(ctx context.Context, productID int64, sort QuestionSort, limit, offset int) ([]Question, int, error) {
	limit, offset = clampPage(limit, offset)
	items, err := s.repo.ListQuestions(ctx, productID, sort, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	total, err := s.repo.CountQuestions(ctx, productID)
	if err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func (s *ugcService) GetQuestion(ctx context.Context, questionID int64) (Question, []Answer, error) {
	q, err := s.repo.GetQuestion(ctx, questionID)
	if err != nil {
		return Question{}, nil, err
	}
	answers, err := s.repo.ListAnswers(ctx, questionID)
	if err != nil {
		return Question{}, nil, err
	}
	return q, answers, nil
}

func (s *ugcService) CreateAnswer(ctx context.Context, in AnswerInput) (Answer, error) {
	if len(in.Body) == 0 {
		return Answer{}, ErrEmptyBody
	}
	if len(in.Body) > maxAnswerBody {
		return Answer{}, ErrBodyTooLong
	}
	// is_seller is set by the handler from the seller_users binding (Tranche 5a).
	return s.repo.InsertAnswerAndRefresh(ctx, in, in.IsSeller)
}

// ── Seller Q&A inbox (Tranche 5a) ─────────────────────────────────────────────

func (s *ugcService) ListSellerQuestions(ctx context.Context, productIDs []int64, onlyUnanswered bool, limit, offset int) ([]Question, int, error) {
	if len(productIDs) == 0 {
		return []Question{}, 0, nil
	}
	limit, offset = clampPage(limit, offset)
	items, err := s.repo.ListSellerInboxQuestions(ctx, productIDs, onlyUnanswered, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	total, err := s.repo.CountSellerInboxQuestions(ctx, productIDs, onlyUnanswered)
	if err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func (s *ugcService) ListUserQuestions(ctx context.Context, userID int64, limit, offset int) ([]Question, int, error) {
	limit, offset = clampPage(limit, offset)
	items, err := s.repo.ListUserQuestions(ctx, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	total, err := s.repo.CountUserQuestions(ctx, userID)
	if err != nil {
		return nil, 0, err
	}
	return items, total, nil
}
