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
