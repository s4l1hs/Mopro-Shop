package eventbus_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/mopro/platform/internal/eventbus"
)

// eventTypeRe matches canonical Mopro event type string literals.
var eventTypeRe = regexp.MustCompile(`^(?:ecom|fin)\.[a-z][a-z0-9._-]*\.v[0-9]+$`)

// buildRegistrySet returns a set of all event types in the registry.
func buildRegistrySet() map[string]struct{} {
	m := make(map[string]struct{}, len(eventbus.Registry))
	for _, e := range eventbus.Registry {
		m[e.EventType] = struct{}{}
	}
	return m
}

// TestRegistry_NoOrphanedEventTypes scans every non-test .go file under
// internal/ and pkg/ for string literals matching the event-type pattern, then
// asserts that each one is present in the registry.
// "Orphaned" means: appears in production code but was never registered.
func TestRegistry_NoOrphanedEventTypes(t *testing.T) {
	repoRoot := findRepoRoot(t)
	registered := buildRegistrySet()

	fset := token.NewFileSet()
	var orphans []string

	searchDirs := []string{
		filepath.Join(repoRoot, "internal"),
		filepath.Join(repoRoot, "pkg"),
		filepath.Join(repoRoot, "cmd"),
	}

	for _, dir := range searchDirs {
		if _, err := os.Stat(dir); os.IsNotExist(err) {
			continue
		}
		err := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}
			if !strings.HasSuffix(path, ".go") {
				return nil
			}
			// Skip test files and the registry itself to avoid self-reference.
			base := filepath.Base(path)
			if strings.HasSuffix(base, "_test.go") || base == "registry.go" {
				return nil
			}

			f, parseErr := parser.ParseFile(fset, path, nil, 0)
			if parseErr != nil {
				return nil // best-effort; malformed files don't block the check
			}
			ast.Inspect(f, func(n ast.Node) bool {
				lit, ok := n.(*ast.BasicLit)
				if !ok || lit.Kind != token.STRING {
					return true
				}
				// Strip surrounding quotes.
				val := strings.Trim(lit.Value, `"`)
				if !eventTypeRe.MatchString(val) {
					return true
				}
				if _, found := registered[val]; !found {
					orphans = append(orphans, val+" ("+path+")")
				}
				return true
			})
			return nil
		})
		if err != nil {
			t.Fatalf("walking %s: %v", dir, err)
		}
	}

	for _, o := range orphans {
		t.Errorf("event type in code but not in registry: %s", o)
	}
}

// TestRegistry_AllProducersExist verifies that the ProducerModule directory
// exists for every non-deprecated registry entry.
func TestRegistry_AllProducersExist(t *testing.T) {
	repoRoot := findRepoRoot(t)

	for _, entry := range eventbus.Registry {
		if entry.Status == eventbus.StatusDeprecatedPendingDelete ||
			entry.Status == eventbus.StatusActiveConsumerNoProducer {
			continue
		}
		// Strip annotation in parentheses (e.g. "internal/payment/sipay (webhook handler)").
		modulePath := strings.SplitN(entry.ProducerModule, " (", 2)[0]
		dir := filepath.Join(repoRoot, modulePath)
		if _, err := os.Stat(dir); os.IsNotExist(err) {
			t.Errorf("registry entry %q: ProducerModule %q does not exist at %s",
				entry.EventType, modulePath, dir)
		}
	}
}

// findRepoRoot walks up from the current working directory until it finds go.mod.
func findRepoRoot(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatal("could not find repo root (no go.mod found)")
		}
		dir = parent
	}
}
