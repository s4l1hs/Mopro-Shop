//go:build contract

package main

// Live-handler contract conformance tests.
//
// Unlike internal/api/contract_test.go (which validates hand-crafted fixtures
// against the spec, and so never sees a handler that omits a field), these call
// the REAL handler with stub services, capture the JSON it actually writes, and
// validate it against the endpoint's OpenAPI schema. This is the systemic catch
// for server↔spec drift — it would have failed on the PD-06 envelope/image_keys
// response the previous handler emitted.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/getkin/kin-openapi/openapi3"
	"github.com/mopro/platform/internal/attachments"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/seller"
	"github.com/mopro/platform/internal/sizefinder"
	"github.com/mopro/platform/pkg/mediaurl"
)

// stubReturnSvc is a no-op order.ReturnService for the GetOrder contract test.
type stubReturnSvc struct{}

func (stubReturnSvc) CreateReturn(context.Context, order.ReturnInput) (order.Return, []order.ReturnItem, error) {
	return order.Return{}, nil, nil
}
func (stubReturnSvc) GetReturn(context.Context, int64, int64) (order.Return, []order.ReturnItem, error) {
	return order.Return{}, nil, nil
}
func (stubReturnSvc) GetReturnHistory(context.Context, int64, int64) ([]order.ReturnStatusEvent, error) {
	return nil, nil
}
func (stubReturnSvc) GetReturnPhotos(context.Context, int64, int64) ([]string, error) {
	return nil, nil
}
func (stubReturnSvc) ListReturns(context.Context, int64, int, int) ([]order.Return, error) {
	return nil, nil
}
func (stubReturnSvc) ComputeActions(context.Context, order.Order, []order.OrderItem) (order.OrderActions, error) {
	return order.OrderActions{}, nil
}
func (stubReturnSvc) ListSellerReturns(context.Context, []int64, string, int, int) ([]order.Return, error) {
	return nil, nil
}
func (stubReturnSvc) SellerApprove(context.Context, int64, []int64) (order.Return, error) {
	return order.Return{}, nil
}
func (stubReturnSvc) SellerReject(context.Context, int64, []int64, string, string) (order.Return, error) {
	return order.Return{}, nil
}

// stubOrderCatalog is a no-op orderCatalogResolver (the test order has no items, so
// neither method is exercised).
type stubOrderCatalog struct{}

func (stubOrderCatalog) GetVariantByID(context.Context, int64) (catalog.Variant, error) {
	return catalog.Variant{}, nil
}
func (stubOrderCatalog) ListProductsByIDs(context.Context, []int64, string, string) ([]catalog.ProductSummaryRow, error) {
	return nil, nil
}

// TestContract_GetOrder_DeliveryAddress proves OR-02: GET /orders/{id} surfaces the
// frozen delivery-address snapshot under order.delivery_address, conforming to the
// DeliveryAddress schema, and asserts the order's status conforms to the (now honest)
// Order status enum.
//
// We validate the delivery_address sub-object + the status field rather than the whole
// order against the Order schema. The status-enum drift is now FIXED (the spec enum
// matches internal/order.OrderStatus — pending_payment/paid/…/partially_refunded), so
// status="paid" conforms. A SEPARATE structural divergence remains: the API envelope
// emits items as a sibling of order ({"order":…, "items":[…]}) while the Order schema
// nests items inside the order, so a whole-order assertion still fails on the missing
// nested "items". Reconciling that is a response-shape/schema change out of this
// gen-drift lane (it would touch the mobile read-path) — documented as a follow-up.
func TestContract_GetOrder_DeliveryAddress(t *testing.T) {
	doc := loadSpec(t)

	orderSvc := &stubOrderSvc{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{
				ID: id, UserID: 1, Status: order.StatusPaid, Currency: "TRY",
				TotalMinor: 12990, CreatedAt: time.Date(2026, 1, 15, 10, 0, 0, 0, time.UTC),
				DeliveryAddress: &order.OrderAddress{
					Label: "Ev", RecipientName: "Ali Veli", Phone: "+905551112233",
					FullAddress: "Atatürk Cad. No:1", Neighborhood: "Merkez Mah.",
					District: "Kadıköy", City: "İstanbul", PostalCode: "34000",
				},
			}, nil, nil
		},
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/orders/7", nil)
	req.SetPathValue("id", "7")
	handleGetOrder(orderSvc, stubReturnSvc{}, &stubPaymentRepo{}, stubOrderCatalog{}, "tr-TR")(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}

	var wrapper struct {
		Order struct {
			Status          string          `json:"status"`
			DeliveryAddress json.RawMessage `json:"delivery_address"`
		} `json:"order"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &wrapper); err != nil {
		t.Fatalf("decode envelope: %v", err)
	}
	// The reconciled enum: status="paid" must now be a member of the Order schema enum.
	assertEnumMember(t, doc, "Order", "status", wrapper.Order.Status)
	if len(wrapper.Order.DeliveryAddress) == 0 || string(wrapper.Order.DeliveryAddress) == "null" {
		t.Fatalf("delivery_address missing: %s", rec.Body.String())
	}
	assertConformsToSchema(t, doc, "DeliveryAddress", wrapper.Order.DeliveryAddress)

	var addr struct {
		RecipientName string `json:"recipient_name"`
		City          string `json:"city"`
		FullAddress   string `json:"full_address"`
	}
	if err := json.Unmarshal(wrapper.Order.DeliveryAddress, &addr); err != nil {
		t.Fatalf("decode delivery_address: %v", err)
	}
	if addr.RecipientName != "Ali Veli" || addr.City != "İstanbul" || addr.FullAddress == "" {
		t.Errorf("delivery_address mismatch: %+v", addr)
	}
}

// loadSpec loads + validates api/openapi.yaml (../../api relative to this file).
func loadSpec(t *testing.T) *openapi3.T {
	t.Helper()
	_, thisFile, _, _ := runtime.Caller(0)
	specPath := filepath.Join(filepath.Dir(thisFile), "..", "..", "api", "openapi.yaml")
	loader := openapi3.NewLoader()
	doc, err := loader.LoadFromFile(specPath)
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	if err := doc.Validate(context.Background()); err != nil {
		t.Fatalf("spec validation: %v", err)
	}
	return doc
}

// assertConformsToSchema round-trips the captured JSON and validates it against
// the named component schema (VisitJSON enforces required fields, types, enums,
// nullability) — the same view a generated client deserializes.
func assertConformsToSchema(t *testing.T, doc *openapi3.T, schemaName string, body []byte) {
	t.Helper()
	schemaRef, ok := doc.Components.Schemas[schemaName]
	if !ok {
		t.Fatalf("schema %q not found in components", schemaName)
	}
	var decoded interface{}
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("unmarshal response: %v\nbody: %s", err, body)
	}
	if err := schemaRef.Value.VisitJSON(decoded); err != nil {
		t.Errorf("handler response does not satisfy schema %q: %v\nJSON: %s", schemaName, err, body)
	}
}

// assertEnumMember checks that value is a declared member of the enum on
// <schemaName>.<property> — used to prove a live serialized value (e.g. an Order
// status) is honest against the spec without validating the whole object (which can
// fail on unrelated structural divergences).
func assertEnumMember(t *testing.T, doc *openapi3.T, schemaName, property, value string) {
	t.Helper()
	schemaRef, ok := doc.Components.Schemas[schemaName]
	if !ok {
		t.Fatalf("schema %q not found in components", schemaName)
	}
	prop, ok := schemaRef.Value.Properties[property]
	if !ok {
		t.Fatalf("property %q not found on schema %q", property, schemaName)
	}
	for _, e := range prop.Value.Enum {
		if s, _ := e.(string); s == value {
			return
		}
	}
	t.Errorf("value %q is not in the %s.%s enum %v (spec drift)", value, schemaName, property, prop.Value.Enum)
}

// TestContract_GetProductDetail_LiveHandler proves GET /products/{id} emits the
// spec-conformant flat Product (PD-06) — incl. variants[].image_urls, the
// gallery field. Fails on the legacy {product, variants, …}/image_keys envelope.
func TestContract_GetProductDetail_LiveHandler(t *testing.T) {
	doc := loadSpec(t)

	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{
					ID: id, SellerID: 1, CategoryID: 30, Brand: "Nike",
					Status: "active", CreatedAt: time.Date(2026, 1, 15, 10, 0, 0, 0, time.UTC),
				},
				[]catalog.Variant{{
					ID: 101, ProductID: id, SKU: "V-1", Color: "Siyah", Size: "M",
					PriceMinor: 129900, PriceCurrency: "TRY", Stock: 5,
					ImageKeys: []string{"products/v1/1.jpg", "products/v1/2.jpg"},
				}},
				[]catalog.ProductTranslation{{
					ProductID: id, Locale: "tr-TR",
					Title: "Nike Dri-FIT", Description: "Pamuklu spor tişört.",
				}},
				nil
		},
	}
	sellerSvc := &stubSellerSvc{
		getByIDFn: func(int64) (seller.Seller, error) {
			return seller.Seller{ID: 1, Slug: "acme-store", DisplayName: "Acme Store"}, nil
		},
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/products/7", nil)
	req.SetPathValue("id", "7")
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	assertConformsToSchema(t, doc, "Product", rec.Body.Bytes())

	// Guard the specific PD-06 regression: image_urls present + CDN-mapped, and
	// no legacy envelope/image_keys leak.
	var flat struct {
		ID       int64 `json:"id"`
		Variants []struct {
			ImageURLs []string `json:"image_urls"`
			ImageKeys []string `json:"image_keys"`
		} `json:"variants"`
		Product json.RawMessage `json:"product"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &flat); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if flat.ID != 7 {
		t.Errorf("id not at top level (envelope leak?): %s", rec.Body.String())
	}
	if flat.Product != nil {
		t.Errorf("legacy 'product' envelope key present: %s", rec.Body.String())
	}
	if len(flat.Variants) != 1 || len(flat.Variants[0].ImageURLs) != 2 {
		t.Fatalf("image_urls not emitted: %s", rec.Body.String())
	}
	if len(flat.Variants[0].ImageKeys) != 0 {
		t.Errorf("legacy image_keys leaked into the variant: %s", rec.Body.String())
	}
}

type stubFavoritesReader struct {
	ids []int64
	err error
}

func (s stubFavoritesReader) ListFavoriteProductIDs(context.Context, int64) ([]int64, error) {
	return s.ids, s.err
}

// TestContract_GetFavorites_LiveHandler proves FAV-02: GET /favorites emits the
// down-sync payload `{product_ids:[…]}` the mobile merges into its local set.
// Hand-written endpoint (favorites aren't in the OpenAPI spec — like reviews,
// PD-07), so the shape is asserted directly.
func TestContract_GetFavorites_LiveHandler(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/favorites", nil)
	handleFavoritesList(stubFavoritesReader{ids: []int64{7, 42, 100}})(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var body struct {
		ProductIDs []int64 `json:"product_ids"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(body.ProductIDs) != 3 || body.ProductIDs[0] != 7 {
		t.Errorf("product_ids mismatch: %v", body.ProductIDs)
	}

	// Empty favorites → a JSON empty array (never null — the client maps it).
	rec2 := httptest.NewRecorder()
	handleFavoritesList(stubFavoritesReader{ids: nil})(rec2, httptest.NewRequest(http.MethodGet, "/favorites", nil))
	var body2 struct {
		ProductIDs []int64 `json:"product_ids"`
	}
	if err := json.Unmarshal(rec2.Body.Bytes(), &body2); err != nil {
		t.Fatalf("empty decode: %v (%s)", err, rec2.Body.String())
	}
	if body2.ProductIDs == nil {
		t.Errorf("empty favorites must emit product_ids:[] not null: %s", rec2.Body.String())
	}
}

// TestContract_GetProductDetail_SellerOfficial proves PD-04: an official seller
// surfaces as Product.seller_official=true on the flat detail response (from
// seller.IsOfficial via the in-process GetByID carrier — no cross-schema JOIN).
func TestContract_GetProductDetail_SellerOfficial(t *testing.T) {
	doc := loadSpec(t)

	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{
					ID: id, SellerID: 1, CategoryID: 30, Brand: "Nike",
					Status: "active", CreatedAt: time.Date(2026, 1, 15, 10, 0, 0, 0, time.UTC),
				},
				[]catalog.Variant{{
					ID: 101, ProductID: id, SKU: "V-1", PriceMinor: 129900,
					PriceCurrency: "TRY", Stock: 5, ImageKeys: []string{"products/v1/1.jpg"},
				}},
				[]catalog.ProductTranslation{{ProductID: id, Locale: "tr-TR", Title: "Nike"}},
				nil
		},
	}
	sellerSvc := &stubSellerSvc{
		getByIDFn: func(int64) (seller.Seller, error) {
			return seller.Seller{ID: 1, Slug: "acme-store", DisplayName: "Acme Store", IsOfficial: true}, nil
		},
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/products/7", nil)
	req.SetPathValue("id", "7")
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	assertConformsToSchema(t, doc, "Product", rec.Body.Bytes())

	var flat struct {
		SellerOfficial bool `json:"seller_official"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &flat); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !flat.SellerOfficial {
		t.Errorf("seller_official should be true for an official seller: %s", rec.Body.String())
	}
}

// TestContract_GetCategoryFacets_LiveHandler validates the PLP-13 facet
// aggregation response against the Facet schema (each bucket has value+count).
func TestContract_GetCategoryFacets_LiveHandler(t *testing.T) {
	doc := loadSpec(t)

	catalogSvc := &stubCatalogSvc{
		facetsFn: func() ([]catalog.Facet, error) {
			return []catalog.Facet{{
				Slug: "renk", Name: "Renk",
				Values: []catalog.FacetValue{{Value: "Siyah", Count: 5}, {Value: "Beyaz", Count: 4}},
			}}, nil
		},
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/categories/31/facets", nil)
	req.SetPathValue("id", "31")
	handleCategoryFacets(catalogSvc, "tr-TR")(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}

	var body struct {
		Facets []json.RawMessage `json:"facets"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v\nbody: %s", err, rec.Body.String())
	}
	if len(body.Facets) != 1 {
		t.Fatalf("want 1 facet, got %d: %s", len(body.Facets), rec.Body.String())
	}
	assertConformsToSchema(t, doc, "Facet", body.Facets[0])
}

// TestContract_GetProductDetail_AttributesArray guards that the detail response
// carries the spec-required `attributes` array (PLP-13 / PD-01) — never null.
func TestContract_GetProductDetail_AttributesArray(t *testing.T) {
	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{ID: id, SellerID: 1, CategoryID: 30, Brand: "Nike", Status: "active"},
				[]catalog.Variant{{ID: 1, SKU: "V", PriceMinor: 100, PriceCurrency: "TRY", Stock: 1, ImageKeys: []string{"k"}}},
				[]catalog.ProductTranslation{{ProductID: id, Locale: "tr-TR", Title: "T", Description: "D"}}, nil
		},
		productAttributesFn: func() ([]catalog.ProductAttribute, error) {
			return []catalog.ProductAttribute{{Slug: "renk", Name: "Renk", Values: []string{"Siyah", "Beyaz"}}}, nil
		},
	}
	sellerSvc := &stubSellerSvc{getByIDFn: func(int64) (seller.Seller, error) {
		return seller.Seller{ID: 1, Slug: "s", DisplayName: "S"}, nil
	}}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/products/7", nil)
	req.SetPathValue("id", "7")
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d", rec.Code)
	}
	var flat struct {
		Attributes []struct {
			Slug   string   `json:"slug"`
			Name   string   `json:"name"`
			Values []string `json:"values"`
		} `json:"attributes"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &flat); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(flat.Attributes) != 1 || flat.Attributes[0].Slug != "renk" || len(flat.Attributes[0].Values) != 2 {
		t.Fatalf("attributes not surfaced: %s", rec.Body.String())
	}
}

// ── PD-07: reviews reviewer-name + photos (live-handler) ──────────────────────
// The reviews endpoint is hand-written (raw-Dio mobile client, not in the
// OpenAPI spec), so this asserts the handler output directly rather than via a
// schema — the same approach #158 used to guard image_urls.

type stubReviewNamer struct{ name string }

func (s stubReviewNamer) GetMe(context.Context, int64) (identity.User, error) {
	return identity.User{Name: s.name}, nil
}

type stubReviewPhotos struct{ keys []string }

func (s stubReviewPhotos) ListByEntity(context.Context, string, int64) ([]attachments.PhotoAttachment, error) {
	out := make([]attachments.PhotoAttachment, len(s.keys))
	for i, k := range s.keys {
		out[i] = attachments.PhotoAttachment{StorageKey: k}
	}
	return out, nil
}

func TestContract_ProductReviews_NameAndPhotos(t *testing.T) {
	catalogSvc := &stubCatalogSvc{
		listReviewsFn: func() ([]catalog.ProductReviewRow, int, error) {
			return []catalog.ProductReviewRow{{
				ID: 9, UserID: 1, Rating: 5, Title: "Harika", Body: "Çok iyi",
				HelpfulCount: 2, CreatedAt: "2026-01-01T00:00:00Z",
			}}, 1, nil
		},
		reviewsSummaryFn: func() (catalog.ReviewsSummary, error) {
			return catalog.ReviewsSummary{
				Distribution: map[int]int{1: 0, 2: 0, 3: 0, 4: 0, 5: 1},
				Average:      5, TotalCount: 1,
			}, nil
		},
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/products/7/reviews", nil)
	req.SetPathValue("id", "7")
	handleProductReviews(catalogSvc,
		stubReviewNamer{name: "Ahmet Yılmaz"},
		stubReviewPhotos{keys: []string{"reviews/9/a.jpg", "reviews/9/b.jpg"}},
	)(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var body struct {
		Items []struct {
			ReviewerName string   `json:"reviewerName"`
			PhotoURLs    []string `json:"photoUrls"`
		} `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v\nbody: %s", err, rec.Body.String())
	}
	if len(body.Items) != 1 {
		t.Fatalf("want 1 item, got %d: %s", len(body.Items), rec.Body.String())
	}
	if body.Items[0].ReviewerName != "A** Y**" {
		t.Errorf("reviewerName: want masked 'A** Y**', got %q", body.Items[0].ReviewerName)
	}
	want := []string{mediaurl.CDNUrl("reviews/9/a.jpg"), mediaurl.CDNUrl("reviews/9/b.jpg")}
	if len(body.Items[0].PhotoURLs) != 2 || body.Items[0].PhotoURLs[0] != want[0] || body.Items[0].PhotoURLs[1] != want[1] {
		t.Errorf("photoUrls: want CDN-mapped %v, got %v", want, body.Items[0].PhotoURLs)
	}
}

// ── Size-fit: live-handler conformance (phase 1) ─────────────────────────────

// TestContract_SizeFit proves the consumer-facing size-fit handlers emit
// spec-conformant shapes. jobs-svc is stubbed at the HTTP seam (the §3.4
// internal hop) — the contract under test is core's, not the network's.
func TestContract_SizeFit(t *testing.T) {
	doc := loadSpec(t)
	chest := 970
	weight := 80000

	jobs := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/internal/sizefit/profile" && r.Method == http.MethodGet:
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(sizefinder.FitProfile{
				UserID: 1, ChestMM: &chest, WeightG: &weight,
				Gender: "male", FitPref: "regular",
			})
		case r.URL.Path == "/internal/sizefit/recommend":
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(sizefinder.Recommendation{
				Status: "ok", GarmentType: "top", Size: "M",
				Signal: "true_to_size", Confidence: "basic",
				Estimated: []string{"chest"}, Source: "standard", ChartApproximate: true,
			})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer jobs.Close()
	t.Setenv("JOBS_SVC_URL", jobs.URL)
	client := newSizefitClient()

	t.Run("GET /me/fit-profile conforms to FitProfileEnvelope", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/me/fit-profile", nil)
		handleGetFitProfile(client)(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
		}
		assertConformsToSchema(t, doc, "FitProfileEnvelope", rec.Body.Bytes())
	})

	t.Run("GET size-recommendation conforms to SizeRecommendation", func(t *testing.T) {
		catalogSvc := &stubCatalogSvc{
			getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
				return catalog.Product{ID: id}, nil, []catalog.ProductTranslation{{
					ProductID: id, Locale: "tr-TR", Title: "Basic Tişört",
				}}, nil
			},
		}
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/products/15/size-recommendation", nil)
		req.SetPathValue("id", "15")
		handleSizeRecommendation(client, catalogSvc, &stubSellerSvc{}, "tr-TR")(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
		}
		assertConformsToSchema(t, doc, "SizeRecommendation", rec.Body.Bytes())
	})
}
