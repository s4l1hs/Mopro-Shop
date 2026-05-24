// API types generated from api/openapi.yaml
// All monetary amounts are in integer minor units (kuruş). Never use floats for money.

// ── Common ────────────────────────────────────────────────────────────────────

export interface FieldError {
  name: string;
  message: string;
}

export interface ApiError {
  code: string;
  message: string;
  trace_id: string;
  fields?: FieldError[];
}

export interface ErrorEnvelope {
  error: ApiError;
}

export interface PaginationMeta {
  page: number;
  per_page: number;
  total: number;
  total_pages: number;
}

export interface CursorPaginationMeta {
  has_more: boolean;
  next_cursor: string | null;
}

// ── Auth ──────────────────────────────────────────────────────────────────────

export interface TokenPair {
  access_token: string;
  token_type: "Bearer";
  expires_in: number;
  refresh_token: string;
  refresh_expires_at: string;
}

export interface OtpRequestBody {
  phone: string;
  market?: string;
}

export interface OtpVerifyBody {
  phone: string;
  code: string;
}

export interface RefreshBody {
  refresh_token: string;
}

// ── User / Identity ───────────────────────────────────────────────────────────

export interface User {
  id: number;
  phone: string;
  name_first: string | null;
  name_last: string | null;
  email: string | null;
  locale: string;
  created_at: string;
  updated_at: string;
}

// ── Address ───────────────────────────────────────────────────────────────────

export interface Address {
  id: number;
  label: string;
  name: string;
  phone: string;
  city: string;
  district: string;
  neighborhood: string | null;
  full_address: string;
  postal_code: string | null;
  is_default: boolean;
}

export interface AddressInput {
  label: string;
  name: string;
  phone: string;
  city: string;
  district: string;
  neighborhood?: string;
  full_address: string;
  postal_code?: string;
  is_default?: boolean;
}

// ── Catalog ───────────────────────────────────────────────────────────────────

export interface Category {
  id: number;
  name: string;
  slug: string;
  parent_id: number | null;
  icon_url: string | null;
  commission_pct_bps: number;
}

export interface CashbackPreview {
  monthly_coin_minor: number;
  currency: string;
}

export interface Variant {
  id: number;
  sku: string;
  color: string | null;
  size: string | null;
  price_minor: number;
  price_currency: string;
  stock: number;
  image_urls: string[];
}

export interface Product {
  id: number;
  seller_id: number;
  seller_name: string;
  category_id: number;
  brand: string;
  status: "active" | "inactive" | "draft";
  title: string;
  description: string;
  variants: Variant[];
  cashback_preview: CashbackPreview;
  created_at: string;
}

export interface ProductSummary {
  id: number;
  seller_id: number;
  category_id: number;
  brand: string;
  status: "active" | "inactive" | "draft";
  title: string;
  price_minor: number;
  price_currency: string;
  cover_image_url: string | null;
  cashback_preview: CashbackPreview;
}

// ── Cart ──────────────────────────────────────────────────────────────────────

export interface CartItem {
  variant_id: number;
  product_id: number;
  title: string;
  image_url: string | null;
  color: string | null;
  size: string | null;
  price_minor: number;
  price_currency: string;
  quantity: number;
  monthly_coin_minor: number;
  coin_currency: string;
}

export interface Cart {
  user_id: number;
  items: CartItem[];
  subtotal_minor: number;
  subtotal_currency: string;
  total_monthly_coin_minor: number;
  coin_currency: string;
}

export interface Reservation {
  id: string;
  expires_at: string;
}

// ── Checkout / Orders ─────────────────────────────────────────────────────────

export type CargoOption = "aras" | "yurtici" | "surat" | "mng" | "hepsijet" | "ptt";

export interface CheckoutRequest {
  address_id: number;
  cargo_option: CargoOption;
  payment_method: {
    type: "card" | "coin_balance";
    saved_card_id?: string | null;
  };
}

export interface CheckoutResponse {
  order_id: number;
  status: "awaiting_payment" | "confirmed";
  total_minor: number;
  currency: string;
  payment: {
    requires_3ds: boolean;
    redirect_url: string | null;
  };
}

export interface OrderItem {
  id: number;
  variant_id: number;
  product_id: number;
  title: string;
  quantity: number;
  price_minor: number;
  price_currency: string;
  commission_pct_bps: number;
}

export type OrderStatus =
  | "pending"
  | "confirmed"
  | "preparing"
  | "shipped"
  | "delivered"
  | "cancelled"
  | "refunded";

export interface Order {
  id: number;
  user_id: number;
  status: OrderStatus;
  items: OrderItem[];
  total_minor: number;
  currency: string;
  cargo_option: CargoOption | null;
  cashback_unlock_at: string | null;
  delivered_at: string | null;
  created_at: string;
}

// ── Cashback ──────────────────────────────────────────────────────────────────

export type CashbackPlanStatus = "active" | "cancelled" | "suspended";

export interface CashbackPlan {
  id: number;
  order_id: number;
  product_id: number;
  product_title: string;
  product_image_url: string | null;
  monthly_amount_minor: number;
  currency: string;
  status: CashbackPlanStatus;
  start_date: string;
  reference_interest_rate_bps: number;
  created_at: string;
}

export type CashbackPaymentStatus = "scheduled" | "paid" | "failed";

export interface CashbackPayment {
  id: number;
  plan_id: number;
  period_yyyymm: string;
  amount_minor: number;
  currency: string;
  status: CashbackPaymentStatus;
  paid_at?: string;
}

// ── Wallet ────────────────────────────────────────────────────────────────────

export interface WalletBalance {
  currency: string;
  amount_minor: number;
  last_updated_at: string;
}

export type WalletTransactionType = "credit" | "debit";
export type WalletTransactionReferenceType = "cashback_payment" | "payout" | "adjustment";

export interface WalletTransaction {
  id: number;
  type: WalletTransactionType;
  amount_minor: number;
  currency: string;
  description: string | null;
  reference_id: number | null;
  reference_type: WalletTransactionReferenceType | null;
  occurred_at: string;
}

// ── Discovery ─────────────────────────────────────────────────────────────────

export interface Banner {
  id: number;
  placement: string;
  image_url: string;
  action_type: "deeplink" | "external" | "none";
  action_url: string | null;
  expires_at: string | null;
}

// ── Paginated responses ───────────────────────────────────────────────────────

export interface PaginatedResponse<T> {
  data: T[];
  pagination: PaginationMeta;
}

export interface CursorResponse<T> {
  data: T[];
  pagination: CursorPaginationMeta;
}
