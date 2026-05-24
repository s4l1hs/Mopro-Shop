"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiFetch } from "@/lib/api-client";
import type {
  AccountSummary,
  Address,
  CashbackContributor,
  CashbackHistoryResponse,
  CashbackSummary,
  LoginEvent,
  Order,
  OrdersListResponse,
  Profile,
  SavedCard,
  Session,
} from "@/lib/types/account";

// ─── Account Dashboard ───────────────────────────────────────────────────────

export function useAccountSummaryQuery() {
  return useQuery({
    queryKey: ["account-summary"],
    queryFn: () => apiFetch<AccountSummary>("/account/summary"),
    staleTime: 60 * 1000,
    retry: 1,
  });
}

// ─── Orders ──────────────────────────────────────────────────────────────────

interface OrdersParams {
  filter?: string;
  q?: string;
  page?: number;
}

export function useOrdersListQuery(params: OrdersParams) {
  const search = new URLSearchParams();
  if (params.filter && params.filter !== "all") search.set("filter", params.filter);
  if (params.q) search.set("q", params.q);
  if (params.page && params.page > 1) search.set("page", String(params.page));
  const qs = search.toString();

  return useQuery({
    queryKey: ["orders-list", params],
    queryFn: () => apiFetch<OrdersListResponse>(`/orders${qs ? `?${qs}` : ""}`),
    staleTime: 30 * 1000,
    retry: 1,
  });
}

export function useOrderDetailQuery(orderId: string) {
  return useQuery({
    queryKey: ["order", orderId],
    queryFn: () => apiFetch<Order>(`/orders/${orderId}`),
    staleTime: 60 * 1000,
    retry: 1,
    enabled: !!orderId,
  });
}

// ─── Cashback ─────────────────────────────────────────────────────────────────

interface CashbackHistoryParams {
  from?: string;
  to?: string;
  page?: number;
}

export function useCashbackSummaryQuery() {
  return useQuery({
    queryKey: ["cashback-summary"],
    queryFn: () => apiFetch<CashbackSummary>("/cashback/summary"),
    staleTime: 60 * 1000,
    retry: 1,
  });
}

export function useCashbackHistoryQuery(params: CashbackHistoryParams = {}) {
  const search = new URLSearchParams();
  if (params.from) search.set("from", params.from);
  if (params.to) search.set("to", params.to);
  if (params.page && params.page > 1) search.set("page", String(params.page));
  const qs = search.toString();

  return useQuery({
    queryKey: ["cashback-history", params],
    queryFn: () => apiFetch<CashbackHistoryResponse>(`/cashback/payouts${qs ? `?${qs}` : ""}`),
    staleTime: 60 * 1000,
    retry: 1,
  });
}

export function useCashbackContributorsQuery() {
  return useQuery({
    queryKey: ["cashback-contributors"],
    queryFn: () => apiFetch<CashbackContributor[]>("/cashback/active-orders"),
    staleTime: 60 * 1000,
    retry: 1,
  });
}

// ─── Addresses ───────────────────────────────────────────────────────────────

export function useAddressesQuery() {
  return useQuery({
    queryKey: ["addresses"],
    queryFn: () => apiFetch<Address[]>("/addresses"),
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}

export function useCreateAddressMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: Omit<Address, "id" | "is_default">) =>
      apiFetch<Address>("/addresses", { method: "POST", body: data }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["addresses"] }),
  });
}

export function useUpdateAddressMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, ...data }: Partial<Address> & { id: string }) =>
      apiFetch<Address>(`/addresses/${id}`, { method: "PUT", body: data }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["addresses"] }),
  });
}

export function useDeleteAddressMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch<void>(`/addresses/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["addresses"] }),
  });
}

export function useSetDefaultAddressMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch<void>(`/addresses/${id}/default`, { method: "PATCH" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["addresses"] }),
  });
}

// ─── Profile ─────────────────────────────────────────────────────────────────

export function useProfileQuery() {
  return useQuery({
    queryKey: ["profile"],
    queryFn: () => apiFetch<Profile>("/profile"),
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}

export function useUpdateProfileMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: Partial<Profile>) =>
      apiFetch<Profile>("/profile", { method: "PATCH", body: data }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["profile"] }),
  });
}

// ─── Security ────────────────────────────────────────────────────────────────

export function useSessionsQuery() {
  return useQuery({
    queryKey: ["sessions"],
    queryFn: () => apiFetch<Session[]>("/auth/sessions"),
    staleTime: 30 * 1000,
    retry: 1,
  });
}

export function useLoginEventsQuery() {
  return useQuery({
    queryKey: ["login-events"],
    queryFn: () => apiFetch<LoginEvent[]>("/auth/login-events"),
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}

export function useRevokeSessionMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (sessionId: string) =>
      apiFetch<void>(`/auth/sessions/${sessionId}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["sessions"] }),
  });
}

export function useRevokeAllSessionsMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => apiFetch<void>("/auth/sessions", { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["sessions"] }),
  });
}

export function useDeleteAccountMutation() {
  return useMutation({
    mutationFn: () => apiFetch<void>("/account", { method: "DELETE" }),
  });
}

// ─── Saved cards ─────────────────────────────────────────────────────────────

export function useSavedCardsQuery() {
  return useQuery({
    queryKey: ["saved-cards"],
    queryFn: () => apiFetch<SavedCard[]>("/payment/cards"),
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}

export function useDeleteCardMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch<void>(`/payment/cards/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["saved-cards"] }),
  });
}

export function useSetDefaultCardMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      apiFetch<void>(`/payment/cards/${id}/default`, { method: "PATCH" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["saved-cards"] }),
  });
}
