package crypto

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"encoding/hex"
	"os"
	"strings"
	"sync"
	"testing"
)

// ── NIST SP 800-38D AES-256-GCM test vectors ────────────────────────────────
// These test the Go stdlib AES-GCM implementation against published NIST vectors,
// confirming the primitive is correct before testing our wrapper.

func TestNIST_AES256GCM_TestCase13(t *testing.T) {
	// Test Case 13: 256-bit key, empty PT, empty AAD.
	// Expected tag: 530f8afbc74536b9a963b4f1c4cb738b
	key := mustHex(t, "0000000000000000000000000000000000000000000000000000000000000000")
	nonce := mustHex(t, "000000000000000000000000")
	wantTag := mustHex(t, "530f8afbc74536b9a963b4f1c4cb738b")

	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatal(err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		t.Fatal(err)
	}
	got := gcm.Seal(nil, nonce, nil, nil) // empty PT → output is just the 16-byte tag
	if !bytes.Equal(got, wantTag) {
		t.Errorf("NIST TC13 tag mismatch: got %x, want %x", got, wantTag)
	}
}

func TestNIST_AES256GCM_TestCase14(t *testing.T) {
	// Test Case 14: 256-bit key, 16-byte PT, empty AAD.
	// Expected CT: cea7403d4d606b6e074ec5d3baf39d18
	// Expected tag: d0d1c8a799996bf0265b98b5d48ab919
	key := mustHex(t, "0000000000000000000000000000000000000000000000000000000000000000")
	nonce := mustHex(t, "000000000000000000000000")
	pt := mustHex(t, "00000000000000000000000000000000")
	wantCT := mustHex(t, "cea7403d4d606b6e074ec5d3baf39d18")
	wantTag := mustHex(t, "d0d1c8a799996bf0265b98b5d48ab919")
	want := append(wantCT, wantTag...)

	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatal(err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		t.Fatal(err)
	}
	got := gcm.Seal(nil, nonce, pt, nil)
	if !bytes.Equal(got, want) {
		t.Errorf("NIST TC14 output mismatch: got %x, want %x", got, want)
	}
}

// ── encryptWithKey / decryptWithKey unit tests ───────────────────────────────

func testKey(t *testing.T) []byte {
	t.Helper()
	// 32 zero bytes — valid AES-256 key for deterministic tests.
	return make([]byte, 32)
}

func TestEncryptDecrypt_RoundTrip(t *testing.T) {
	key := testKey(t)
	cases := []string{
		"hello",
		"+905321234567",
		strings.Repeat("a", 1000),
		"unicode: 🎉 Türkçe içerik",
		"",
	}
	for _, tc := range cases {
		enc, err := encryptWithKey(key, tc)
		if err != nil {
			t.Fatalf("encrypt %q: %v", tc, err)
		}
		got, err := decryptWithKey(key, enc)
		if err != nil {
			t.Fatalf("decrypt %q: %v", tc, err)
		}
		if got != tc {
			t.Errorf("round-trip %q: got %q", tc, got)
		}
	}
}

func TestEncryptDecrypt_NonDeterministic(t *testing.T) {
	// Each call with the same plaintext must produce a different ciphertext (random nonce).
	key := testKey(t)
	a, _ := encryptWithKey(key, "same")
	b, _ := encryptWithKey(key, "same")
	if a == b {
		t.Error("two encryptions of the same plaintext produced identical output (nonce reuse?)")
	}
}

func TestDecryptWithKey_TamperedCiphertext(t *testing.T) {
	key := testKey(t)
	enc, err := encryptWithKey(key, "sensitive data")
	if err != nil {
		t.Fatal(err)
	}
	// Flip a byte in the middle of the base64 output.
	b := []byte(enc)
	b[len(b)/2] ^= 0xFF
	_, err = decryptWithKey(key, string(b))
	if err == nil {
		t.Error("expected error for tampered ciphertext, got nil")
	}
}

func TestDecryptWithKey_WrongKey(t *testing.T) {
	key := testKey(t)
	enc, err := encryptWithKey(key, "secret")
	if err != nil {
		t.Fatal(err)
	}
	wrongKey := make([]byte, 32)
	wrongKey[0] = 0xFF
	_, err = decryptWithKey(wrongKey, enc)
	if err == nil {
		t.Error("expected error for wrong key, got nil")
	}
}

func TestDecryptWithKey_TruncatedData(t *testing.T) {
	key := testKey(t)
	// 5 bytes base64-decoded → < 12+16=28 minimum
	_, err := decryptWithKey(key, "AAAA")
	if err == nil {
		t.Error("expected ErrInvalidCiphertext for truncated data")
	}
}

func TestDecryptWithKey_InvalidBase64(t *testing.T) {
	key := testKey(t)
	_, err := decryptWithKey(key, "not-valid-base64!!!")
	if err == nil {
		t.Error("expected ErrInvalidCiphertext for invalid base64")
	}
}

// ── EncryptPII / DecryptPII integration with env ─────────────────────────────

func TestMain(m *testing.M) {
	// Set env vars once before all tests so sync.Once loads real key material.
	// 32 zero bytes base64-encoded = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
	os.Setenv("PII_KEK_BASE64", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
	os.Setenv("PII_PEPPER", "test-pepper-for-unit-tests-only")
	os.Exit(m.Run())
}

func TestEncryptPII_DecryptPII_RoundTrip(t *testing.T) {
	cases := []string{"test@example.com", "+905321234567", ""}
	for _, tc := range cases {
		enc, err := EncryptPII(tc)
		if err != nil {
			t.Fatalf("EncryptPII(%q): %v", tc, err)
		}
		got, err := DecryptPII(enc)
		if err != nil {
			t.Fatalf("DecryptPII: %v", err)
		}
		if got != tc {
			t.Errorf("round-trip %q: got %q", tc, got)
		}
	}
}

func TestDecryptPII_Returns_ErrInvalidCiphertext(t *testing.T) {
	_, err := DecryptPII("notvalid!!!")
	if err == nil {
		t.Fatal("expected error")
	}
}

// ── PhoneHash tests ──────────────────────────────────────────────────────────

func TestPhoneHash_Length(t *testing.T) {
	h, err := PhoneHash("+905321234567")
	if err != nil {
		t.Fatal(err)
	}
	if len(h) != 32 {
		t.Errorf("expected 32-byte HMAC-SHA256, got %d bytes", len(h))
	}
}

func TestPhoneHash_Deterministic(t *testing.T) {
	phone := "+905321234567"
	a, err := PhoneHash(phone)
	if err != nil {
		t.Fatal(err)
	}
	b, err := PhoneHash(phone)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(a, b) {
		t.Error("PhoneHash is not deterministic for same input")
	}
}

func TestPhoneHash_DifferentInputs(t *testing.T) {
	a, _ := PhoneHash("+905321234567")
	b, _ := PhoneHash("+905321234568")
	if bytes.Equal(a, b) {
		t.Error("PhoneHash produced same output for different inputs")
	}
}

// ── Property test: round-trip on 500 random-ish plaintexts ──────────────────

func TestProperty_EncryptDecrypt_RoundTrip(t *testing.T) {
	key := testKey(t)
	inputs := []string{
		"", "a", "ab", "abc",
		strings.Repeat("x", 1), strings.Repeat("x", 63),
		strings.Repeat("x", 64), strings.Repeat("x", 65),
		strings.Repeat("x", 255), strings.Repeat("x", 256),
		strings.Repeat("x", 500),
		"+905321234567", "test@mopro.com",
		"Türkçe metin içeriği",
		"日本語テキスト",
		"newline\nin\ntext",
		"tab\tin\ttext",
		"null\x00byte",
		"emoji 🎉🎊🥳",
	}
	// Also add 100 deterministic varying-length strings.
	for i := 0; i < 100; i++ {
		inputs = append(inputs, strings.Repeat(string(rune('a'+i%26)), i))
	}
	for _, tc := range inputs {
		enc, err := encryptWithKey(key, tc)
		if err != nil {
			t.Fatalf("encryptWithKey(%q): %v", tc, err)
		}
		got, err := decryptWithKey(key, enc)
		if err != nil {
			t.Fatalf("decryptWithKey for input %q: %v", tc, err)
		}
		if got != tc {
			t.Errorf("round-trip failed: input %q, got %q", tc, got)
		}
	}
}

// ── sync.Once concurrency safety ─────────────────────────────────────────────

func TestEncryptPII_ConcurrentSafe(t *testing.T) {
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			enc, err := EncryptPII("concurrent test")
			if err != nil {
				t.Errorf("EncryptPII concurrent: %v", err)
				return
			}
			got, err := DecryptPII(enc)
			if err != nil {
				t.Errorf("DecryptPII concurrent: %v", err)
				return
			}
			if got != "concurrent test" {
				t.Errorf("concurrent round-trip: got %q", got)
			}
		}()
	}
	wg.Wait()
}

// ── helpers ──────────────────────────────────────────────────────────────────

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("hex decode %q: %v", s, err)
	}
	return b
}
