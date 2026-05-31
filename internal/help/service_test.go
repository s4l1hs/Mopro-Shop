package help

import (
	"context"
	"strings"
	"testing"
)

type fakeRepo struct {
	cats     []CategoryRow
	articles []ArticleRow
	one      ArticleRow
	oneErr   error
}

func (f *fakeRepo) ListCategories(context.Context) ([]CategoryRow, error) { return f.cats, nil }
func (f *fakeRepo) ListArticles(context.Context, string) ([]ArticleRow, error) {
	return f.articles, nil
}
func (f *fakeRepo) GetArticle(context.Context, string) (ArticleRow, error) { return f.one, f.oneErr }
func (f *fakeRepo) SearchArticles(context.Context, string, int) ([]ArticleRow, error) {
	return f.articles, nil
}

func TestLocaleFallback(t *testing.T) {
	repo := &fakeRepo{
		one: ArticleRow{
			Slug:  "x",
			Title: map[string]string{"tr": "Başlık", "en": "Title"}, // no de
			Body:  map[string]string{"en": "Only English body"},     // no tr/de
		},
	}
	s := NewService(repo, nil)

	// de-DE requested: title missing de → falls back to tr; body missing de+tr → en.
	a, err := s.GetArticle(context.Background(), "x", "de-DE")
	if err != nil {
		t.Fatal(err)
	}
	if a.Title != "Başlık" {
		t.Errorf("title fallback: got %q want tr 'Başlık'", a.Title)
	}
	if a.Body != "Only English body" {
		t.Errorf("body fallback: got %q want en", a.Body)
	}

	// en requested resolves directly.
	a2, _ := s.GetArticle(context.Background(), "x", "en-US")
	if a2.Title != "Title" {
		t.Errorf("en title: got %q", a2.Title)
	}
}

func TestLocaleLang(t *testing.T) {
	for in, want := range map[string]string{
		"de-DE": "de", "tr_TR": "tr", "en": "en", "": "tr", "AR-ae": "ar",
	} {
		if got := localeLang(in); got != want {
			t.Errorf("localeLang(%q)=%q want %q", in, got, want)
		}
	}
}

func TestSnippetMarksMatch(t *testing.T) {
	body := "## Başlık\n\nİade talebini başlatmak için sipariş detayına git ve İade butonuna dokun."
	snip := snippet(body, "iade")
	if !strings.Contains(snip, "**") {
		t.Errorf("snippet should bold the match: %q", snip)
	}
	if strings.Contains(snip, "##") {
		t.Errorf("snippet should strip markdown headers: %q", snip)
	}
	if len([]rune(snip)) > 200 {
		t.Errorf("snippet too long: %d runes", len([]rune(snip)))
	}
}

func TestListCategoriesResolves(t *testing.T) {
	repo := &fakeRepo{cats: []CategoryRow{
		{Slug: "account", Title: map[string]string{"tr": "Hesabım", "en": "My Account"}, ArticleCount: 6},
	}}
	s := NewService(repo, nil)
	cats, err := s.ListCategories(context.Background(), "en")
	if err != nil {
		t.Fatal(err)
	}
	if cats[0].Title != "My Account" || cats[0].ArticleCount != 6 {
		t.Errorf("got %+v", cats[0])
	}
}
