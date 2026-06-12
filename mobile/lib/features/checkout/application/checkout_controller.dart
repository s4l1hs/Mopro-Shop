import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/checkout/data/checkout_repository.dart';
import 'package:mopro/features/checkout/data/checkout_repository_impl.dart';
import 'package:mopro/features/checkout/data/checkout_response_dto.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:uuid/uuid.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final checkoutRepositoryProvider = Provider<CheckoutRepository>((ref) {
  return CheckoutRepositoryImpl(ref.watch(dioProvider));
});

// ── State ─────────────────────────────────────────────────────────────────────

/// Supported card-installment counts (PD-05, taksit). Mirrors the backend's
/// allowed set; 1 = single charge (tek çekim). Interest-free: the charged
/// total never changes with the count.
const kInstallmentOptions = [1, 3, 6, 9, 12];

class CheckoutState {
  const CheckoutState({
    this.selectedAddress,
    this.paymentMethod = 'card',
    this.installments = 1,
    this.isInitiating = false,
    this.response,
    this.invoiceId,
    this.paymentError,
    this.error,
  });

  final Address? selectedAddress;
  final String paymentMethod;
  final int installments; // PD-05: chosen taksit count; 1 = single charge
  final bool isInitiating;
  final CheckoutResponseDto? response;
  final String? invoiceId;      // idempotency key sent; used as polling handle
  final String? paymentError;   // Turkish user-facing 3DS failure message
  final AppError? error;        // network / API error

  int? get selectedAddressId => selectedAddress?.id;
  bool get canProceed => selectedAddress != null && !isInitiating;

  CheckoutState copyWith({
    Address? selectedAddress,
    String? paymentMethod,
    int? installments,
    bool? isInitiating,
    CheckoutResponseDto? response,
    String? invoiceId,
    String? paymentError,
    AppError? error,
    bool clearError = false,
    bool clearResponse = false,
    bool clearPaymentError = false,
    bool clearInvoiceId = false,
  }) =>
      CheckoutState(
        selectedAddress: selectedAddress ?? this.selectedAddress,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        installments: installments ?? this.installments,
        isInitiating: isInitiating ?? this.isInitiating,
        response: clearResponse ? null : response ?? this.response,
        invoiceId: clearInvoiceId ? null : invoiceId ?? this.invoiceId,
        paymentError: clearPaymentError ? null : paymentError ?? this.paymentError,
        error: clearError ? null : error ?? this.error,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutState();

  void selectAddress(Address address) {
    state = state.copyWith(
      selectedAddress: address,
      clearError: true,
      clearPaymentError: true,
    );
  }

  void selectPaymentMethod(String method) {
    state = state.copyWith(paymentMethod: method, clearError: true);
  }

  /// PD-05: pick a card-installment count. Ignores unsupported values
  /// (defensive — the UI only offers [kInstallmentOptions]).
  void selectInstallments(int count) {
    if (!kInstallmentOptions.contains(count)) return;
    state = state.copyWith(installments: count, clearError: true);
  }

  void setPaymentError(String message) {
    state = state.copyWith(
      paymentError: message,
      clearResponse: true,
      clearInvoiceId: true,
    );
  }

  void clearPaymentError() {
    state = state.copyWith(clearPaymentError: true);
  }

  void reset() {
    state = const CheckoutState();
  }

  Future<void> placeOrder() async {
    final address = state.selectedAddress;
    if (address == null) return;

    state = state.copyWith(
      isInitiating: true,
      clearError: true,
      clearResponse: true,
      clearPaymentError: true,
      clearInvoiceId: true,
    );

    // Split "Ali Yılmaz" → buyerName="Ali", buyerSurname="Yılmaz".
    final nameParts = address.name.trim().split(RegExp(r'\s+'));
    final buyerName = nameParts.length > 1
        ? nameParts.sublist(0, nameParts.length - 1).join(' ')
        : address.name;
    final buyerSurname = nameParts.length > 1 ? nameParts.last : '';

    final idempotencyKey = const Uuid().v4();

    try {
      final repo = ref.read(checkoutRepositoryProvider);
      final response = await repo.initiate(
        buyerName: buyerName,
        buyerSurname: buyerSurname,
        idempotencyKey: idempotencyKey,
        addressId: address.id, // OR-02: capture the ship-to snapshot on the order
        installments: state.installments, // PD-05: taksit (interest-free)
        couponCode: ref.read(cartProvider).couponCode,
      );
      state = state.copyWith(
        isInitiating: false,
        response: response,
        invoiceId: idempotencyKey,
      );
    } on DioException catch (e) {
      final err = e.error;
      state = state.copyWith(
        isInitiating: false,
        error: err is AppError
            ? err
            : NetworkError(message: e.message ?? ''),
      );
    } catch (e) {
      state = state.copyWith(
        isInitiating: false,
        error: UnknownError(statusCode: 0, message: e.toString()),
      );
    }
  }
}
