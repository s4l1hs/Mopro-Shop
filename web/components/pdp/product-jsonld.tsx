import type { ProductDetail } from "@/lib/types/product";

interface ProductJsonLdProps {
  product: ProductDetail;
  canonicalUrl: string;
}

export function ProductJsonLd({ product, canonicalUrl }: ProductJsonLdProps) {
  const displayPrice = product.discount_price_minor ?? product.price_minor;
  const images = [
    ...(product.images ?? []),
    product.cover_image_url,
  ].filter(Boolean);

  const jsonLd: Record<string, unknown> = {
    "@context": "https://schema.org",
    "@type": "Product",
    name: product.title,
    image: images,
    url: canonicalUrl,
    offers: {
      "@type": "Offer",
      price: (displayPrice / 100).toFixed(2),
      priceCurrency: product.currency ?? "TRY",
      availability:
        (product.stock ?? 1) === 0
          ? "https://schema.org/OutOfStock"
          : "https://schema.org/InStock",
      url: canonicalUrl,
    },
  };

  if (product.description) jsonLd.description = product.description;
  if (product.brand) {
    jsonLd.brand = { "@type": "Brand", name: product.brand };
  }
  if (product.rating) {
    jsonLd.aggregateRating = {
      "@type": "AggregateRating",
      ratingValue: product.rating.stars.toFixed(1),
      reviewCount: product.rating.count,
    };
  }

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(jsonLd).replace(/<\/script>/gi, "<\\/script>"),
      }}
    />
  );
}
