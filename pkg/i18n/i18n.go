// Package i18n resolves localised translation keys for the active market locale.
// User-facing strings are NEVER hardcoded; they are resolved through this package.
package i18n

// Resolver maps translation keys to localised strings for a given locale.
type Resolver interface {
	// T returns the translated string for key in locale.
	T(locale, key string, args ...any) string
}

// TODO(mopro:placeholder): implement go-i18n backed Resolver loading from
// /mobile/assets/translations/<locale>.json
// Unblocked by: Phase 1 (config loader) and translation file creation
