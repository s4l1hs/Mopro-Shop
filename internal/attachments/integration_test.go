//go:build integration

package attachments_test

// Integration tests for the media repo + migration 0079 round-trip, against the
// shared ephemeral PG16:
//
//	go test -tags=integration ./internal/media/...

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/attachments"
	"github.com/mopro/platform/internal/storage"
)

const defaultTestDSN = "postgres://ecom_admin:test123@localhost:6433/mopro_ecom"

var integPool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("MEDIA_TEST_DSN")
	if dsn == "" {
		dsn = defaultTestDSN
	}
	ctx := context.Background()
	var err error
	integPool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "media integration: pool: %v\n", err)
		os.Exit(1)
	}
	if err := integPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "media integration: ping: %v\n", err)
		os.Exit(1)
	}
	for _, f := range []string{
		"../../migrations/ecom/0079_photo_attachments.down.sql",
		"../../migrations/ecom/0079_photo_attachments.up.sql",
	} {
		sql, rerr := os.ReadFile(f)
		if rerr != nil {
			fmt.Fprintf(os.Stderr, "media integration: read %s: %v\n", f, rerr)
			os.Exit(1)
		}
		if _, eerr := integPool.Exec(ctx, string(sql)); eerr != nil {
			fmt.Fprintf(os.Stderr, "media integration: exec %s: %v\n", f, eerr)
			os.Exit(1)
		}
	}
	code := m.Run()
	integPool.Close()
	os.Exit(code)
}

func newSvc(t *testing.T) (attachments.Service, attachments.Repository) {
	t.Helper()
	repo := attachments.NewRepository(integPool)
	store, err := storage.NewFSStorage(t.TempDir())
	if err != nil {
		t.Fatalf("fs storage: %v", err)
	}
	return attachments.NewService(repo, store), repo
}

func orphan(t *testing.T, svc attachments.Service, userID int64, entityType string) attachments.PhotoAttachment {
	t.Helper()
	a, err := svc.Upload(context.Background(), attachments.UploadInput{
		UserID: userID, EntityType: entityType, ContentType: "image/png",
		Ext: "png", ByteSize: 5, WidthPx: 300, HeightPx: 300,
		Reader: bytes.NewReader([]byte("bytes")),
	})
	if err != nil {
		t.Fatalf("upload orphan: %v", err)
	}
	return a
}

func TestIntegration_MigrationRoundTrip(t *testing.T) {
	ctx := context.Background()
	// up applied in TestMain → table queryable.
	if _, err := integPool.Exec(ctx, `SELECT 1 FROM attachments_schema.photo_attachments LIMIT 1`); err != nil {
		t.Fatalf("table not present after up: %v", err)
	}
	mustExec(t, "../../migrations/ecom/0079_photo_attachments.down.sql")
	if _, err := integPool.Exec(ctx, `SELECT 1 FROM attachments_schema.photo_attachments LIMIT 1`); err == nil {
		t.Fatal("table should be gone after down")
	}
	mustExec(t, "../../migrations/ecom/0079_photo_attachments.up.sql")
}

func TestIntegration_UploadAndAttach(t *testing.T) {
	ctx := context.Background()
	svc, repo := newSvc(t)
	const user, reviewID int64 = 7, 9100
	a1 := orphan(t, svc, user, attachments.EntityReview)
	a2 := orphan(t, svc, user, attachments.EntityReview)

	// Attach both inside a tx → sorted, attached.
	if err := repo.WithTx(ctx, func(tx pgx.Tx) error {
		return svc.AttachInTx(ctx, tx, attachments.EntityReview, reviewID, []int64{a1.ID, a2.ID}, user)
	}); err != nil {
		t.Fatalf("attach: %v", err)
	}
	got, err := svc.ListByEntity(ctx, attachments.EntityReview, reviewID)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(got) != 2 || got[0].ID != a1.ID || got[1].ID != a2.ID {
		t.Fatalf("attached set wrong: %+v", got)
	}
	if got[0].PublicURL == "" {
		t.Error("PublicURL not populated")
	}
}

func TestIntegration_AttachOwnershipReattachLimit(t *testing.T) {
	ctx := context.Background()
	svc, repo := newSvc(t)

	// Ownership: user 8's orphan can't be attached by user 7.
	other := orphan(t, svc, 8, attachments.EntityReview)
	err := repo.WithTx(ctx, func(tx pgx.Tx) error {
		return svc.AttachInTx(ctx, tx, attachments.EntityReview, 9200, []int64{other.ID}, 7)
	})
	if err != attachments.ErrNotOwned {
		t.Fatalf("ownership: want ErrNotOwned, got %v", err)
	}

	// Re-attach: once attached, attaching again fails (entity_id not null).
	a := orphan(t, svc, 7, attachments.EntityReview)
	if e := repo.WithTx(ctx, func(tx pgx.Tx) error {
		return svc.AttachInTx(ctx, tx, attachments.EntityReview, 9300, []int64{a.ID}, 7)
	}); e != nil {
		t.Fatalf("first attach: %v", e)
	}
	if e := repo.WithTx(ctx, func(tx pgx.Tx) error {
		return svc.AttachInTx(ctx, tx, attachments.EntityReview, 9301, []int64{a.ID}, 7)
	}); e != attachments.ErrNotOwned {
		t.Fatalf("re-attach: want ErrNotOwned, got %v", e)
	}

	// Limit: 6 orphans → review cap is 5 → ErrLimitExceeded.
	ids := make([]int64, 0, 6)
	for i := 0; i < 6; i++ {
		ids = append(ids, orphan(t, svc, 7, attachments.EntityReview).ID)
	}
	if e := repo.WithTx(ctx, func(tx pgx.Tx) error {
		return svc.AttachInTx(ctx, tx, attachments.EntityReview, 9400, ids, 7)
	}); e != attachments.ErrLimitExceeded {
		t.Fatalf("limit: want ErrLimitExceeded, got %v", e)
	}
}

func mustExec(t *testing.T, file string) {
	t.Helper()
	sql, err := os.ReadFile(file)
	if err != nil {
		t.Fatalf("read %s: %v", file, err)
	}
	if _, err := integPool.Exec(context.Background(), string(sql)); err != nil {
		t.Fatalf("exec %s: %v", file, err)
	}
}
