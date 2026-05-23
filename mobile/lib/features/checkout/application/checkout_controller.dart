import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/checkout/data/checkout_repository.dart';
import 'package:mopro/features/checkout/data/checkout_repository_impl.dart';
import 'package:mopro/features/checkout/data/checkout_response_dto.dart';
import 'package:uuid/uuid.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final checkoutRepositoryProvider = Provider<CheckoutRepository>((ref) {
  return CheckoutRepositoryImpl(ref.watch(dioProvider));
});

// ── State ─────────────────────────────────────────────────────────────────────

class CheckoutState {
  const CheckoutState({
    this.selectedAddressId,
    this.paymentMethod = 'card',
    this.isInitiating = false,
    this.response,
    this.error,
  });

  final int? selectedAddressId;
  final String paymentMethod;
  final bool isInitiating;
  final CheckoutResponseDto? response;
  final AppError? error;

  bool get canProceed => selectedAddressId != null && !isInitiating;

  CheckoutState copyWith({
    int? selectedAddressId,
    String? paymentMethod,
    bool? isInitiating,
    CheckoutResponseDto? response,
    AppError? error,
    bool clearError = false,
    bool clearResponse = false,
  }) =>
      CheckoutState(
        selectedAddressId: selectedAddressId ?? this.selectedAddressId,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        isInitiating: isInitiating ?? this.isInitiating,
        response: clearResponse ? null : response ?? this.response,
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

  void selectAddress(int id) {
    state = state.copyWith(selectedAddressId: id, clearError: true);
  }

  void selectPaymentMethod(String method) {
    state = state.copyWith(paymentMethod: method, clearError: true);
  }

  void reset() {
    state = const CheckoutState();
  }

  Future<void> placeOrder() async {
    final addressId = state.selectedAddressId;
    if (addressId == null) return;

    state = state.copyWith(
      isInitiating: true,
      clearError: true,
      clearResponse: true,
    );

    try {
      final repo = ref.read(checkoutRepositoryProvider);
      final idempotencyKey = const Uuid().v4();
      final response = await repo.initiate(
        addressId: addressId,
        paymentMethod: state.paymentMethod,
        idempotencyKey: idempotencyKey,
      );
      state = state.copyWith(
        isInitiating: false,
        response: response,
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
