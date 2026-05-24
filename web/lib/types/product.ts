export interface Product {
  id: number;
  slug?: string;
  title: string;
  brand?: string;
  price_minor: number;
  currency?: string;
  cover_image_url: string;
  commission_pct_bps?: number;
  stock?: number;
}

export interface ProductListResponse {
  items: Product[];
  total: number;
  page: number;
  per_page: number;
}

export interface ProductDetail extends Product {
  images?: string[];
  description?: string;
  specs?: Record<string, string>;
  rating?: { stars: number; count: number };
  discount_price_minor?: number;
  category_slug?: string;
  category_name?: string;
  parent_category_slug?: string;
  parent_category_name?: string;
}
