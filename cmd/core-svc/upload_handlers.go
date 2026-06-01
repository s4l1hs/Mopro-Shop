package main

import (
	"bytes"
	"image"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"time"

	// Register decoders so image.DecodeConfig can read dimensions.
	_ "image/jpeg"
	_ "image/png"

	_ "golang.org/x/image/webp"

	"github.com/mopro/platform/internal/attachments"
	"github.com/mopro/platform/internal/identity/middleware"
)

const (
	maxPhotoBytes   = 5 << 20 // 5 MB
	minPhotoDim     = 200
	maxPhotoDim     = 4096
	uploadsPerHour  = 50
	uploadRateAfter = time.Hour
)

// allowedMIME maps the sniffed content type → file extension.
var allowedMIME = map[string]string{
	"image/jpeg": "jpg",
	"image/png":  "png",
	"image/webp": "webp",
}

// uploadLimiter is a per-instance fixed-window rate limiter (50 uploads/user/hr).
// In-memory is acceptable on the single-VDS deployment (CLAUDE.md §1); a
// Redis-backed limiter is a Backlog refinement for multi-instance.
type uploadLimiter struct {
	mu      sync.Mutex
	windows map[int64]*uploadWindow
}
type uploadWindow struct {
	count int
	start time.Time
}

func newUploadLimiter() *uploadLimiter {
	return &uploadLimiter{windows: map[int64]*uploadWindow{}}
}

func (l *uploadLimiter) allow(userID int64, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	w := l.windows[userID]
	if w == nil || now.Sub(w.start) >= uploadRateAfter {
		l.windows[userID] = &uploadWindow{count: 1, start: now}
		return true
	}
	if w.count >= uploadsPerHour {
		return false
	}
	w.count++
	return true
}

// handleUploadPhoto: POST /uploads/photos (auth). Multipart {file, entity_type}.
// Validates size + MIME (magic-number sniff, not the client header) + dimensions,
// stores the bytes, and inserts an orphan attachment. 503 when storage is
// disabled (no bucket provisioned yet — ADR-0004).
func handleUploadPhoto(attachmentsSvc attachments.Service, storageEnabled bool, limiter *uploadLimiter) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !storageEnabled || attachmentsSvc == nil {
			jsonError(w, "photo upload not available", http.StatusServiceUnavailable)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		if !limiter.allow(userID, time.Now()) {
			jsonError(w, "rate_limit_exceeded", http.StatusTooManyRequests)
			return
		}

		entityType := r.FormValue("entity_type")
		if entityType != attachments.EntityReview && entityType != attachments.EntityReturnItem {
			jsonError(w, "invalid entity_type", http.StatusUnprocessableEntity)
			return
		}

		file, _, err := r.FormFile("file")
		if err != nil {
			jsonError(w, "missing file", http.StatusBadRequest)
			return
		}
		defer file.Close()

		// Read with a hard cap: maxPhotoBytes+1 detects oversize.
		data, err := io.ReadAll(io.LimitReader(file, maxPhotoBytes+1))
		if err != nil {
			jsonError(w, "read failed", http.StatusBadRequest)
			return
		}
		if len(data) > maxPhotoBytes {
			jsonError(w, "file too large (max 5MB)", http.StatusRequestEntityTooLarge)
			return
		}

		// MIME by magic-number sniff — never trust the client Content-Type.
		sniff := http.DetectContentType(data)
		ext, ok := allowedMIME[sniff]
		if !ok {
			jsonError(w, "unsupported media type", http.StatusUnsupportedMediaType)
			return
		}

		// Dimensions by decoding the header. Rejects malformed images + renames.
		cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil || cfg.Width < minPhotoDim || cfg.Height < minPhotoDim ||
			cfg.Width > maxPhotoDim || cfg.Height > maxPhotoDim {
			jsonError(w, "invalid image dimensions", http.StatusUnprocessableEntity)
			return
		}

		// MODERATION_HOOK: when integration ships, invoke content moderation here
		// and reject inappropriate uploads. Tracked as Backlog (ADR-0004).
		// VIRUS_SCAN_HOOK: when integration ships, invoke virus/malware scanning
		// here and quarantine flagged files. Tracked as Backlog (ADR-0004).

		att, err := attachmentsSvc.Upload(r.Context(), attachments.UploadInput{
			UserID:      userID,
			EntityType:  entityType,
			ContentType: sniff,
			Ext:         ext,
			ByteSize:    len(data),
			WidthPx:     cfg.Width,
			HeightPx:    cfg.Height,
			Reader:      bytes.NewReader(data),
		})
		if err != nil {
			slog.Error("upload: attachments.Upload", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusCreated, map[string]any{
			"id":           att.ID,
			"storage_key":  att.StorageKey,
			"public_url":   att.PublicURL,
			"content_type": att.ContentType,
			"byte_size":    att.ByteSize,
			"width_px":     att.WidthPx,
			"height_px":    att.HeightPx,
		})
	}
}
