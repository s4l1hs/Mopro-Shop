package sizefinder

import "strings"

// ClassifyTitle maps a product title to a garment type via a deterministic TR
// keyword table — the phase-1 fallback until curated `garment_type` product
// attributes exist (PLP-13 write-path). APPROXIMATE by design (flagged in every
// API response); non-apparel titles match nothing → ("", false) → no_chart.
//
// Order matters: more specific garments (dress/skirt/outerwear) are checked
// before generic top/bottom words so "elbise" never falls through to a top.
func ClassifyTitle(title string) (GarmentType, bool) {
	t := strings.ToLower(title)
	contains := func(words ...string) bool {
		for _, w := range words {
			if strings.Contains(t, w) {
				return true
			}
		}
		return false
	}
	switch {
	case contains("elbise"):
		return GarmentDress, true
	case contains("etek"):
		return GarmentSkirt, true
	case contains("mont", "kaban", "ceket", "yelek", "parka", "trençkot", "palto"):
		return GarmentOuterwear, true
	case contains("pantolon", "şort", "tayt", "jean", "kot ", "eşofman altı", "jogger"):
		return GarmentBottom, true
	case contains("tişört", "t-shirt", "tshirt", "gömlek", "sweat", "kazak", "hırka",
		"bluz", "polo yaka", "atlet", "body", "crop", "hoodie", "eşofman üstü"):
		return GarmentTop, true
	}
	return "", false
}
