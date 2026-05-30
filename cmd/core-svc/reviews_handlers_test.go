package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity/middleware"
)

// newReviewsGetRequest builds a GET /products/{id}/reviews request with the path
// value pre-set (the stdlib mux normally does this).
func newReviewsGetRequest(productID string, query string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/products/"+productID+"/reviews?"+query, nil)
	r.SetPathValue("id", productID)
	return r
}

func TestHandleProductReviews_ShapeAndSummary(t *testing.T) {
	stub := &stubCatalogSvc{
		listReviewsFn: func() ([]catalog.ProductReviewRow, int, error) {
			return []catalog.ProductReviewRow{
				{ID: 1, UserID: 7, Rating: 5, Title: "Harika", Body: "Çok iyi", HelpfulCount: 3, VotedByCurrentUser: false, CreatedAt: "2026-01-01T00:00:00Z"},
			}, 1, nil
		},
		reviewsSummaryFn: func() (catalog.ReviewsSummary, error) {
			return catalog.ReviewsSummary{
				Average:      4.5,
				Distribution: map[int]int{1: 0, 2: 0, 3: 0, 4: 1, 5: 1},
				TotalCount:   2,
			}, nil
		},
	}
	rec := httptest.NewRecorder()
	handleProductReviews(stub)(rec, newReviewsGetRequest("123", "sort=newest&page=1&pageSize=10"))

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var resp struct {
		Items []struct {
			ID                 int64 `json:"id"`
			HelpfulCount       int   `json:"helpfulCount"`
			VotedByCurrentUser bool  `json:"votedByCurrentUser"`
		} `json:"items"`
		Total    int `json:"total"`
		Page     int `json:"page"`
		PageSize int `json:"pageSize"`
		Summary  struct {
			Average      float64        `json:"average"`
			Distribution map[string]int `json:"distribution"`
			TotalCount   int            `json:"totalCount"`
		} `json:"summary"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	if len(resp.Items) != 1 || resp.Items[0].HelpfulCount != 3 || resp.Items[0].VotedByCurrentUser {
		t.Errorf("items wrong: %+v", resp.Items)
	}
	if resp.Total != 1 || resp.Page != 1 || resp.PageSize != 10 {
		t.Errorf("pagination wrong: total=%d page=%d pageSize=%d", resp.Total, resp.Page, resp.PageSize)
	}
	if resp.Summary.Average != 4.5 || resp.Summary.TotalCount != 2 {
		t.Errorf("summary wrong: %+v", resp.Summary)
	}
	if resp.Summary.Distribution["5"] != 1 || resp.Summary.Distribution["4"] != 1 || resp.Summary.Distribution["1"] != 0 {
		t.Errorf("distribution wrong: %+v", resp.Summary.Distribution)
	}
}

func TestHandleProductReviews_BadParams(t *testing.T) {
	stub := &stubCatalogSvc{}
	cases := []struct {
		name  string
		query string
	}{
		{"invalid sort", "sort=banana"},
		{"page zero", "page=0"},
		{"pageSize over max", "pageSize=51"},
		{"pageSize zero", "pageSize=0"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			handleProductReviews(stub)(rec, newReviewsGetRequest("123", tc.query))
			if rec.Code != http.StatusBadRequest {
				t.Errorf("want 400 got %d (%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestHandleProductReviews_DefaultsSortAndPageSize(t *testing.T) {
	stub := &stubCatalogSvc{
		listReviewsFn: func() ([]catalog.ProductReviewRow, int, error) { return []catalog.ProductReviewRow{}, 0, nil },
	}
	rec := httptest.NewRecorder()
	handleProductReviews(stub)(rec, newReviewsGetRequest("123", ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var resp struct {
		Page     int `json:"page"`
		PageSize int `json:"pageSize"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Page != 1 || resp.PageSize != 10 {
		t.Errorf("defaults wrong: page=%d pageSize=%d", resp.Page, resp.PageSize)
	}
}

func newHelpfulPostRequest(productID, reviewID string, userID int64) *http.Request {
	r := httptest.NewRequest(http.MethodPost, "/products/"+productID+"/reviews/"+reviewID+"/helpful", nil)
	r.SetPathValue("id", productID)
	r.SetPathValue("reviewId", reviewID)
	if userID != 0 {
		r = r.WithContext(middleware.ContextWithUserID(r.Context(), userID))
	}
	return r
}

func TestHandleReviewHelpfulVote_GuestUnauthorized(t *testing.T) {
	stub := &stubCatalogSvc{}
	rec := httptest.NewRecorder()
	handleReviewHelpfulVote(stub)(rec, newHelpfulPostRequest("123", "5", 0))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401 got %d", rec.Code)
	}
	var resp struct {
		Error string `json:"error"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Error != "auth_required" {
		t.Errorf("want auth_required got %q (%s)", resp.Error, rec.Body.String())
	}
}

func TestHandleReviewHelpfulVote_ReviewNotFound(t *testing.T) {
	stub := &stubCatalogSvc{
		reviewProductIDFn: func(int64) (int64, error) { return 0, catalog.ErrReviewNotFound },
	}
	rec := httptest.NewRecorder()
	handleReviewHelpfulVote(stub)(rec, newHelpfulPostRequest("123", "999", 7))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404 got %d (%s)", rec.Code, rec.Body.String())
	}
}

func TestHandleReviewHelpfulVote_ProductMismatch(t *testing.T) {
	stub := &stubCatalogSvc{
		// Review 5 belongs to product 999, not the URL's 123.
		reviewProductIDFn: func(int64) (int64, error) { return 999, nil },
	}
	rec := httptest.NewRecorder()
	handleReviewHelpfulVote(stub)(rec, newHelpfulPostRequest("123", "5", 7))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404 got %d (%s)", rec.Code, rec.Body.String())
	}
}

func TestHandleReviewHelpfulVote_HappyPath(t *testing.T) {
	stub := &stubCatalogSvc{
		reviewProductIDFn: func(int64) (int64, error) { return 123, nil },
		toggleHelpfulFn: func() (catalog.HelpfulVoteResult, error) {
			return catalog.HelpfulVoteResult{Voted: true, HelpfulCount: 4}, nil
		},
	}
	rec := httptest.NewRecorder()
	handleReviewHelpfulVote(stub)(rec, newHelpfulPostRequest("123", "5", 7))
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var resp struct {
		HelpfulCount int  `json:"helpfulCount"`
		Voted        bool `json:"voted"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !resp.Voted || resp.HelpfulCount != 4 {
		t.Errorf("want voted=true count=4 got %+v", resp)
	}
}
