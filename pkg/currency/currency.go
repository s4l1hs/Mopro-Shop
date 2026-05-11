// Package currency defines the Code type and currency validation helpers.
// Currency codes are always read from ref_schema.currencies; never hardcoded in business logic.
package currency

// Code is a validated ISO-4217 currency code or a Mopro custom coin code (e.g. TRY_COIN).
type Code string

// Validate returns true if the code is non-empty.
// TODO(mopro:placeholder): validate against ref_schema.currencies at runtime
// Unblocked by: Phase 0.2 (ref_schema seed) and Phase 1 (DB connectivity)
func (c Code) Validate() bool {
	return c != ""
}

// String implements fmt.Stringer.
func (c Code) String() string {
	return string(c)
}
