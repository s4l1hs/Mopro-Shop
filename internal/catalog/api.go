// Package catalog manages product listings, variants, multi-language translations,
// and category commission reads from ref_schema.
// Other modules (cart, order, search) import ONLY the Service interface from this package.
package catalog

import "context"

// Service is the public interface of the catalog module.
// It is the ONLY exported API. Other modules must import this interface, never
// the concrete service or repository types.
type Service interface {
	CreateProduct(ctx context.Context, in CreateProductRequest) (Product, error)
	AddVariant(ctx context.Context, productID int64, in AddVariantRequest) (Variant, error)
	UpdateTranslation(ctx context.Context, productID int64, locale, title, description string) error
	GetByID(ctx context.Context, id int64) (Product, []Variant, []ProductTranslation, error)
	Search(ctx context.Context, query, locale, market string) ([]Product, error)
	GetCommissionForCategory(ctx context.Context, market string, categoryID int64) (CategoryCommission, error)
	GetVariantByID(ctx context.Context, variantID int64) (Variant, error)
}

// Repository is the storage interface used only by service.go.
// Other modules must not import this; they use the Service interface.
type Repository interface {
	InsertProduct(ctx context.Context, p Product) (Product, error)
	InsertVariant(ctx context.Context, v Variant) (Variant, error)
	UpsertTranslation(ctx context.Context, t ProductTranslation) error
	GetByID(ctx context.Context, id int64) (Product, []Variant, []ProductTranslation, error)
	SearchProducts(ctx context.Context, query, locale, market string) ([]Product, error)
	GetCommission(ctx context.Context, market string, categoryID int64) (CategoryCommission, error)
	IsCurrencyActive(ctx context.Context, code string) (bool, error)
	GetVariantByID(ctx context.Context, variantID int64) (Variant, error)
}
