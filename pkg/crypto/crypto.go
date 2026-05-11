// Package crypto provides AES-GCM envelope encryption for PII fields.
// All PII (national_id, phone, email, address) MUST be encrypted via EncryptPII before storage.
package crypto

import "errors"

// ErrInvalidCiphertext is returned when decryption fails.
var ErrInvalidCiphertext = errors.New("crypto: invalid ciphertext")

// EncryptPII encrypts plaintext PII using AES-GCM envelope encryption.
// The KEK (key encryption key) is loaded from the PII_KEK_BASE64 environment variable.
// TODO(mopro:placeholder): implement AES-GCM envelope encryption with key rotation support
// Unblocked by: Phase 1 (config loader) and production KEK provisioning
func EncryptPII(_ string) (string, error) {
	return "", errors.New("crypto: EncryptPII not yet implemented")
}

// DecryptPII decrypts a ciphertext produced by EncryptPII.
// TODO(mopro:placeholder): implement AES-GCM decryption
func DecryptPII(_ string) (string, error) {
	return "", ErrInvalidCiphertext
}
