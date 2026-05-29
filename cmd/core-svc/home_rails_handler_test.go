package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

func eightRails() []catalog.HomeRailRow {
	rows := make([]catalog.HomeRailRow, 8)
	for i := range rows {
		rows[i] = catalog.HomeRailRow{
			RailKey: "k", TitleTR: "T", TitleEN: "T",
		}
	}
	return rows
}

func railsCount(t *testing.T, url string) int {
	t.Helper()
	svc := &stubCatalogSvc{homeRailsRows: eightRails()}
	rec := httptest.NewRecorder()
	handleHomeRails(svc, "tr-TR")(rec, httptest.NewRequest(http.MethodGet, url, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	var body struct {
		Data []struct {
			Key string `json:"key"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return len(body.Data)
}

func TestHomeRails_LayoutCap(t *testing.T) {
	if n := railsCount(t, "/home/rails?layout=desktop"); n != 6 {
		t.Errorf("desktop: got %d rails, want 6", n)
	}
	if n := railsCount(t, "/home/rails?layout=mobile"); n != 3 {
		t.Errorf("mobile: got %d rails, want 3", n)
	}
	if n := railsCount(t, "/home/rails"); n != 3 {
		t.Errorf("default: got %d rails, want 3", n)
	}
}
