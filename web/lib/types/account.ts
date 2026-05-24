export type OrderStatus =
  | "pending_payment"
  | "paid"
  | "shipped"
  | "delivered"
  | "cancelled"
  | "refunded";

export interface OrderItem {
  id: string;
  product_id: number;
  product_slug?: string;
  title: string;
  brand?: string;
  cover_image_url: string;
  quantity: number;
  unit_price_minor: number;
  currency: string;
}

export interface CashbackPayment {
  period_yyyymm: string;
  amount_minor: number;
  status: "paid" | "pending" | "current";
  paid_at: string | null;
}

export interface Order {
  id: string;
  order_number: string;
  created_at: string;
  status: OrderStatus;
  total_minor: number;
  currency: string;
  monthly_cashback_minor: number;
  items: OrderItem[];
  tracking_number?: string;
  carrier?: string;
  delivery_address?: Address;
  payment_last_four?: string;
  payment_holder_name?: string;
  cashback_plan_status?: "active" | "cancelled" | "pending";
  cashback_schedule?: CashbackPayment[];
  shipping_minor?: number;
}

export interface OrdersListResponse {
  orders: Order[];
  total: number;
  page: number;
  per_page: number;
}

export interface AccountSummary {
  monthly_cashback_minor: number;
  monthly_cashback_active_orders: number;
  total_earned_minor: number;
  active_orders_count: number;
  in_transit_count: number;
  preparing_count: number;
  next_payout_minor: number;
  next_payout_date: string;
  recent_orders: Order[];
}

export interface CashbackChartPoint {
  month: string;
  earned_minor: number;
  expected_minor: number;
}

export interface CashbackSummary {
  total_monthly_minor: number;
  active_plan_count: number;
  total_earned_minor: number;
  next_payout_minor: number;
  next_payout_date: string;
  chart_data: CashbackChartPoint[];
}

export interface CashbackHistoryItem {
  id: string;
  period_yyyymm: string;
  amount_minor: number;
  status: "paid" | "pending";
  paid_at: string | null;
  order_count: number;
  orders?: Array<{ id: string; order_number: string; amount_minor: number }>;
}

export interface CashbackHistoryResponse {
  items: CashbackHistoryItem[];
  total: number;
  page: number;
  per_page: number;
}

export interface CashbackContributor {
  order_id: string;
  order_number: string;
  monthly_amount_minor: number;
  plan_start_date: string;
  months_active: number;
}

export interface Address {
  id: string;
  label?: string;
  full_name: string;
  phone: string;
  city: string;
  district: string;
  address_line: string;
  postal_code?: string;
  is_default: boolean;
}

export interface Profile {
  first_name: string;
  last_name: string;
  email: string;
  phone: string;
  birth_date?: string;
  gender?: "female" | "male" | "other" | "prefer_not_to_say";
  tax_id?: string;
  avatar_url?: string;
}

export interface Session {
  id: string;
  device: string;
  location: string;
  created_at: string;
  last_active_at: string;
  is_current: boolean;
}

export interface LoginEvent {
  id: string;
  created_at: string;
  ip: string;
  location: string;
  device: string;
}

export interface SavedCard {
  id: string;
  brand: "visa" | "mastercard" | "troy" | "unknown";
  last_four: string;
  holder_name: string;
  expiry: string;
  is_default: boolean;
}
