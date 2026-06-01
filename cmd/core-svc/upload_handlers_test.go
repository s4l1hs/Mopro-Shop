package main

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/png"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/attachments"
	"github.com/mopro/platform/internal/identity/middleware"
)

type fakeMediaSvc struct{ uploads int }

func (f *fakeMediaSvc) Upload(_ context.Context, in attachments.UploadInput) (attachments.PhotoAttachment, error) {
	f.uploads++
	return attachments.PhotoAttachment{
		ID: 1, StorageKey: "review/1/x." + in.Ext, ContentType: in.ContentType,
		ByteSize: in.ByteSize, WidthPx: in.WidthPx, HeightPx: in.HeightPx,
		PublicURL: "https://cdn/review/1/x." + in.Ext,
	}, nil
}
func (f *fakeMediaSvc) AttachInTx(context.Context, pgx.Tx, string, int64, []int64, int64) error {
	return nil
}
func (f *fakeMediaSvc) ListByEntity(context.Context, string, int64) ([]attachments.PhotoAttachment, error) {
	return nil, nil
}

// pngBytes builds a w×h opaque PNG.
func pngBytes(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for x := 0; x < w; x++ {
		for y := 0; y < h; y++ {
			img.Set(x, y, color.RGBA{200, 78, 0, 255})
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

func multipartReq(t *testing.T, entityType string, fileName string, data []byte) *http.Request {
	t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	_ = mw.WriteField("entity_type", entityType)
	if data != nil {
		fw, _ := mw.CreateFormFile("file", fileName)
		_, _ = fw.Write(data)
	}
	_ = mw.Close()
	r := httptest.NewRequest(http.MethodPost, "/uploads/photos", &body)
	r.Header.Set("Content-Type", mw.FormDataContentType())
	// Simulate RequireAuth having run.
	r = r.WithContext(middleware.ContextWithUserID(r.Context(), 7))
	return r
}

func run(t *testing.T, svc attachments.Service, enabled bool, lim *uploadLimiter, r *http.Request) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	handleUploadPhoto(svc, enabled, lim)(rec, r)
	return rec
}

func TestUpload_DisabledReturns503(t *testing.T) {
	rec := run(t, &fakeMediaSvc{}, false, newUploadLimiter(),
		multipartReq(t, "review", "p.png", pngBytes(300, 300)))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("want 503, got %d", rec.Code)
	}
}

func TestUpload_ValidationGauntlet(t *testing.T) {
	cases := []struct {
		name       string
		entityType string
		file       string
		data       []byte
		want       int
	}{
		{"valid png", "review", "p.png", pngBytes(300, 300), http.StatusCreated},
		{"valid return_item", "return_item", "p.png", pngBytes(300, 300), http.StatusCreated},
		{"bad entity_type", "profile", "p.png", pngBytes(300, 300), http.StatusUnprocessableEntity},
		{"missing file", "review", "", nil, http.StatusBadRequest},
		{"oversize", "review", "p.png", make([]byte, maxPhotoBytes+1), http.StatusRequestEntityTooLarge},
		{"wrong MIME (text)", "review", "p.png", []byte("just some text, not an image at all"), http.StatusUnsupportedMediaType},
		{"exe renamed .jpg", "review", "x.jpg", []byte("MZ\x90\x00\x03\x00\x00\x00 not a real image"), http.StatusUnsupportedMediaType},
		{"too small", "review", "p.png", pngBytes(100, 100), http.StatusUnprocessableEntity},
		{"too large dims", "review", "p.png", pngBytes(5000, 100), http.StatusUnprocessableEntity},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := run(t, &fakeMediaSvc{}, true, newUploadLimiter(),
				multipartReq(t, tc.entityType, tc.file, tc.data))
			if rec.Code != tc.want {
				t.Fatalf("status: want %d got %d (%s)", tc.want, rec.Code, rec.Body.String())
			}
		})
	}
}

func TestUpload_RateLimit(t *testing.T) {
	lim := newUploadLimiter()
	svc := &fakeMediaSvc{}
	var last int
	for i := 0; i < uploadsPerHour+1; i++ {
		rec := run(t, svc, true, lim, multipartReq(t, "review", "p.png", pngBytes(300, 300)))
		last = rec.Code
	}
	if last != http.StatusTooManyRequests {
		t.Fatalf("want 429 after %d uploads, got %d", uploadsPerHour, last)
	}
}
