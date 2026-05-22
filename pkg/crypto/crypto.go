// Package crypto provides AES-256-GCM envelope encryption and HMAC-SHA256 hashing for PII fields.
// All PII (national_id, phone, email, address) MUST be encrypted via EncryptPII before storage.
package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
)

// ErrInvalidCiphertext is returned when decryption fails (auth tag mismatch or corrupt data).
var ErrInvalidCiphertext = errors.New("crypto: invalid ciphertext")

var (
	kekOnce sync.Once
	kekKey  []byte
	kekErr  error

	pepperOnce sync.Once
	pepperKey  []byte
	pepperErr  error
)

func loadKEK() ([]byte, error) {
	kekOnce.Do(func() {
		raw := os.Getenv("PII_KEK_BASE64")
		if raw == "" {
			kekErr = errors.New("crypto: PII_KEK_BASE64 not set")
			return
		}
		key, err := base64.StdEncoding.DecodeString(raw)
		if err != nil {
			kekErr = fmt.Errorf("crypto: PII_KEK_BASE64 decode: %w", err)
			return
		}
		if len(key) != 32 {
			kekErr = fmt.Errorf("crypto: PII_KEK_BASE64 must decode to 32 bytes, got %d", len(key))
			return
		}
		kekKey = key
	})
	return kekKey, kekErr
}

func loadPepper() ([]byte, error) {
	pepperOnce.Do(func() {
		raw := os.Getenv("PII_PEPPER")
		if raw == "" {
			pepperErr = errors.New("crypto: PII_PEPPER not set")
			return
		}
		pepperKey = []byte(raw)
	})
	return pepperKey, pepperErr
}

// encryptWithKey encrypts plaintext using AES-256-GCM with the supplied 32-byte key.
// Output: base64StdEncoding(12-byte nonce || ciphertext || 16-byte auth tag).
// A fresh random nonce is generated for every call.
func encryptWithKey(key []byte, plaintext string) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("crypto: aes cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("crypto: gcm: %w", err)
	}
	nonce := make([]byte, gcm.NonceSize()) // 12 bytes for standard GCM
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("crypto: nonce rand: %w", err)
	}
	// Seal appends ciphertext||tag to nonce; result is nonce||ciphertext||tag.
	sealed := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// decryptWithKey decrypts output produced by encryptWithKey.
func decryptWithKey(key []byte, encoded string) (string, error) {
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return "", ErrInvalidCiphertext
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("crypto: aes cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("crypto: gcm: %w", err)
	}
	nonceSize := gcm.NonceSize()
	if len(data) < nonceSize+gcm.Overhead() {
		return "", ErrInvalidCiphertext
	}
	nonce, ct := data[:nonceSize], data[nonceSize:]
	pt, err := gcm.Open(nil, nonce, ct, nil)
	if err != nil {
		return "", ErrInvalidCiphertext
	}
	return string(pt), nil
}

// EncryptPII encrypts plaintext PII using AES-256-GCM.
// Key is loaded once from PII_KEK_BASE64 (base64-encoded 32-byte key).
// Output format: base64(12-byte nonce || ciphertext || 16-byte auth tag).
func EncryptPII(plaintext string) (string, error) {
	key, err := loadKEK()
	if err != nil {
		return "", err
	}
	return encryptWithKey(key, plaintext)
}

// DecryptPII decrypts a ciphertext produced by EncryptPII.
// Returns ErrInvalidCiphertext on any authentication or decoding failure.
func DecryptPII(encoded string) (string, error) {
	key, err := loadKEK()
	if err != nil {
		return "", err
	}
	return decryptWithKey(key, encoded)
}

// PhoneHash returns a 32-byte HMAC-SHA256 of phone using PII_PEPPER as the MAC key.
// Used for indexed lookup without storing plaintext; output is stable for the same phone + pepper.
func PhoneHash(phone string) ([]byte, error) {
	pepper, err := loadPepper()
	if err != nil {
		return nil, err
	}
	mac := hmac.New(sha256.New, pepper)
	mac.Write([]byte(phone))
	return mac.Sum(nil), nil
}
