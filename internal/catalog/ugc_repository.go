package catalog

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

const ugcUniqueViolation = "23505"

type ugcRepository struct {
	pool *pgxpool.Pool
}

// NewUGCRepository returns a UGCRepository backed by a pgx pool.
func NewUGCRepository(pool *pgxpool.Pool) UGCRepository { return &ugcRepository{pool: pool} }

func (r *ugcRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("catalog.ugc: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// ── Reviews ───────────────────────────────────────────────────────────────────

// InsertReview atomically writes the review row + its initial revision.
func (r *ugcRepository) InsertReview(ctx context.Context, in ReviewInput) (Review, error) {
	rec := Review{ProductID: in.ProductID, UserID: in.UserID, Rating: in.Rating, Title: in.Title, Body: in.Body, Status: "published"}
	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		e := tx.QueryRow(ctx,
			`INSERT INTO catalog_schema.product_reviews
			   (product_id, user_id, rating, title, body, status, submitted_locale)
			 VALUES ($1,$2,$3,$4,$5,'published',$6)
			 RETURNING id, created_at, updated_at`,
			in.ProductID, in.UserID, in.Rating, in.Title, in.Body, in.SubmittedLocale).
			Scan(&rec.ID, &rec.CreatedAt, &rec.UpdatedAt)
		if e != nil {
			var pgErr *pgconn.PgError
			if errors.As(e, &pgErr) && pgErr.Code == ugcUniqueViolation {
				return ErrReviewExists
			}
			return fmt.Errorf("catalog.ugc: insert review: %w", e)
		}
		return r.InsertReviewRevision(ctx, tx, rec.ID, in.Rating, in.Title, in.Body)
	})
	if err != nil {
		return Review{}, err
	}
	return rec, nil
}

func (r *ugcRepository) InsertReviewRevision(ctx context.Context, tx pgx.Tx, reviewID int64, rating int, title, body string) error {
	_, err := tx.Exec(ctx,
		`INSERT INTO catalog_schema.product_review_revisions (review_id, rating, title, body)
		 VALUES ($1,$2,$3,$4)`, reviewID, rating, title, body)
	if err != nil {
		return fmt.Errorf("catalog.ugc: insert revision: %w", err)
	}
	return nil
}

func (r *ugcRepository) UpdateReviewRow(ctx context.Context, tx pgx.Tx, userID, reviewID int64, in ReviewInput) (Review, error) {
	rec := Review{ID: reviewID, ProductID: in.ProductID, UserID: userID, Rating: in.Rating, Title: in.Title, Body: in.Body, Status: "published"}
	err := tx.QueryRow(ctx,
		`UPDATE catalog_schema.product_reviews
		    SET rating=$3, title=$4, body=$5, updated_at=now()
		  WHERE id=$1 AND user_id=$2 AND status <> 'deleted'
		 RETURNING product_id, created_at, updated_at`,
		reviewID, userID, in.Rating, in.Title, in.Body).
		Scan(&rec.ProductID, &rec.CreatedAt, &rec.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Review{}, ErrReviewNotFound
		}
		return Review{}, fmt.Errorf("catalog.ugc: update review: %w", err)
	}
	return rec, nil
}

func (r *ugcRepository) SoftDeleteReview(ctx context.Context, userID, reviewID int64) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE catalog_schema.product_reviews SET status='deleted', updated_at=now()
		  WHERE id=$1 AND user_id=$2 AND status <> 'deleted'`, reviewID, userID)
	if err != nil {
		return fmt.Errorf("catalog.ugc: soft delete: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrReviewNotFound
	}
	return nil
}

func (r *ugcRepository) ListUserReviews(ctx context.Context, userID int64, limit, offset int) ([]UserReview, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT r.id, r.product_id, r.user_id, r.rating, COALESCE(r.title,''),
		        COALESCE(r.body,''), r.status, r.created_at, r.updated_at,
		        COALESCE(t.title, '')
		   FROM catalog_schema.product_reviews r
		   LEFT JOIN catalog_schema.product_translations t
		     ON t.product_id = r.product_id AND t.locale = 'tr-TR'
		  WHERE r.user_id=$1 AND r.status='published'
		  ORDER BY r.created_at DESC, r.id DESC
		  LIMIT $2 OFFSET $3`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("catalog.ugc: list user reviews: %w", err)
	}
	defer rows.Close()
	var out []UserReview
	for rows.Next() {
		var u UserReview
		if err := rows.Scan(&u.ID, &u.ProductID, &u.UserID, &u.Rating, &u.Title,
			&u.Body, &u.Status, &u.CreatedAt, &u.UpdatedAt, &u.ProductTitle); err != nil {
			return nil, fmt.Errorf("catalog.ugc: scan user review: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func (r *ugcRepository) CountUserReviews(ctx context.Context, userID int64) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM catalog_schema.product_reviews WHERE user_id=$1 AND status='published'`, userID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("catalog.ugc: count user reviews: %w", err)
	}
	return n, nil
}

func (r *ugcRepository) UserReviewID(ctx context.Context, userID, productID int64) (int64, error) {
	var id int64
	err := r.pool.QueryRow(ctx,
		`SELECT id FROM catalog_schema.product_reviews
		  WHERE user_id=$1 AND product_id=$2 AND status='published'`, userID, productID).Scan(&id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, nil
		}
		return 0, fmt.Errorf("catalog.ugc: user review id: %w", err)
	}
	return id, nil
}

func (r *ugcRepository) GetReviewForRevision(ctx context.Context, reviewID int64) (Review, error) {
	var rec Review
	err := r.pool.QueryRow(ctx,
		`SELECT id, product_id, user_id, rating, COALESCE(title,''), COALESCE(body,''), status, created_at, updated_at
		   FROM catalog_schema.product_reviews WHERE id=$1`, reviewID).
		Scan(&rec.ID, &rec.ProductID, &rec.UserID, &rec.Rating, &rec.Title, &rec.Body, &rec.Status, &rec.CreatedAt, &rec.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Review{}, ErrReviewNotFound
		}
		return Review{}, fmt.Errorf("catalog.ugc: get review: %w", err)
	}
	return rec, nil
}

// ── Q&A ───────────────────────────────────────────────────────────────────────

func (r *ugcRepository) InsertQuestion(ctx context.Context, in QuestionInput) (Question, error) {
	q := Question{ProductID: in.ProductID, UserID: in.UserID, AuthorName: in.AuthorName, Body: in.Body}
	err := r.pool.QueryRow(ctx,
		`INSERT INTO catalog_schema.product_questions (product_id, user_id, author_name, body, submitted_locale)
		 VALUES ($1,$2,$3,$4,$5) RETURNING id, answer_count, created_at`,
		in.ProductID, in.UserID, in.AuthorName, in.Body, in.SubmittedLocale).
		Scan(&q.ID, &q.AnswerCount, &q.CreatedAt)
	if err != nil {
		return Question{}, fmt.Errorf("catalog.ugc: insert question: %w", err)
	}
	return q, nil
}

func questionsOrder(sort QuestionSort) string {
	if sort == QuestionSortMostAnswered {
		return "answer_count DESC, created_at DESC, id DESC"
	}
	return "created_at DESC, id DESC"
}

func (r *ugcRepository) ListQuestions(ctx context.Context, productID int64, sort QuestionSort, limit, offset int) ([]Question, error) {
	q := fmt.Sprintf(
		`SELECT id, product_id, user_id, author_name, body, answer_count, created_at
		   FROM catalog_schema.product_questions
		  WHERE product_id=$1 AND status='published'
		  ORDER BY %s LIMIT $2 OFFSET $3`, questionsOrder(sort))
	rows, err := r.pool.Query(ctx, q, productID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("catalog.ugc: list questions: %w", err)
	}
	defer rows.Close()
	return scanQuestions(rows)
}

func (r *ugcRepository) CountQuestions(ctx context.Context, productID int64) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM catalog_schema.product_questions WHERE product_id=$1 AND status='published'`, productID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("catalog.ugc: count questions: %w", err)
	}
	return n, nil
}

func (r *ugcRepository) GetQuestion(ctx context.Context, questionID int64) (Question, error) {
	var q Question
	err := r.pool.QueryRow(ctx,
		`SELECT id, product_id, user_id, author_name, body, answer_count, created_at
		   FROM catalog_schema.product_questions WHERE id=$1 AND status='published'`, questionID).
		Scan(&q.ID, &q.ProductID, &q.UserID, &q.AuthorName, &q.Body, &q.AnswerCount, &q.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Question{}, ErrQuestionNotFound
		}
		return Question{}, fmt.Errorf("catalog.ugc: get question: %w", err)
	}
	return q, nil
}

func (r *ugcRepository) ListAnswers(ctx context.Context, questionID int64) ([]Answer, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, question_id, user_id, author_name, is_seller, body, created_at
		   FROM catalog_schema.product_answers
		  WHERE question_id=$1 AND status='published'
		  ORDER BY created_at ASC, id ASC`, questionID)
	if err != nil {
		return nil, fmt.Errorf("catalog.ugc: list answers: %w", err)
	}
	defer rows.Close()
	var out []Answer
	for rows.Next() {
		var a Answer
		if err := rows.Scan(&a.ID, &a.QuestionID, &a.UserID, &a.AuthorName, &a.IsSeller, &a.Body, &a.CreatedAt); err != nil {
			return nil, fmt.Errorf("catalog.ugc: scan answer: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// InsertAnswerAndRefresh inserts the answer and refreshes the denormalized
// product_questions.answer_count in the same tx (authoritative: product_answers).
func (r *ugcRepository) InsertAnswerAndRefresh(ctx context.Context, in AnswerInput, isSeller bool) (Answer, error) {
	a := Answer{QuestionID: in.QuestionID, UserID: in.UserID, AuthorName: in.AuthorName, IsSeller: isSeller, Body: in.Body}
	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		if e := tx.QueryRow(ctx,
			`INSERT INTO catalog_schema.product_answers (question_id, user_id, author_name, is_seller, body, submitted_locale)
			 VALUES ($1,$2,$3,$4,$5,$6) RETURNING id, created_at`,
			in.QuestionID, in.UserID, in.AuthorName, isSeller, in.Body, in.SubmittedLocale).
			Scan(&a.ID, &a.CreatedAt); e != nil {
			return e
		}
		_, e := tx.Exec(ctx,
			`UPDATE catalog_schema.product_questions
			    SET answer_count = (SELECT COUNT(*) FROM catalog_schema.product_answers
			                         WHERE question_id=$1 AND status='published'),
			        updated_at = now()
			  WHERE id=$1`, in.QuestionID)
		return e
	})
	if err != nil {
		return Answer{}, fmt.Errorf("catalog.ugc: insert answer: %w", err)
	}
	return a, nil
}

func (r *ugcRepository) ListUserQuestions(ctx context.Context, userID int64, limit, offset int) ([]Question, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, product_id, user_id, author_name, body, answer_count, created_at
		   FROM catalog_schema.product_questions
		  WHERE user_id=$1 AND status='published'
		  ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("catalog.ugc: list user questions: %w", err)
	}
	defer rows.Close()
	return scanQuestions(rows)
}

func (r *ugcRepository) CountUserQuestions(ctx context.Context, userID int64) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM catalog_schema.product_questions WHERE user_id=$1 AND status='published'`, userID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("catalog.ugc: count user questions: %w", err)
	}
	return n, nil
}

func scanQuestions(rows pgx.Rows) ([]Question, error) {
	var out []Question
	for rows.Next() {
		var q Question
		if err := rows.Scan(&q.ID, &q.ProductID, &q.UserID, &q.AuthorName, &q.Body, &q.AnswerCount, &q.CreatedAt); err != nil {
			return nil, fmt.Errorf("catalog.ugc: scan question: %w", err)
		}
		out = append(out, q)
	}
	return out, rows.Err()
}
