import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/return_dto.dart';

/// The four steps of the return flow, mirrored into the URL `?step=` param.
enum ReturnStep { items, reasons, review, confirm }

ReturnStep returnStepFromName(String? name) => switch (name) {
      'reasons' => ReturnStep.reasons,
      'review' => ReturnStep.review,
      'confirm' => ReturnStep.confirm,
      _ => ReturnStep.items,
    };

extension ReturnStepName on ReturnStep {
  String get name => switch (this) {
        ReturnStep.items => 'items',
        ReturnStep.reasons => 'reasons',
        ReturnStep.review => 'review',
        ReturnStep.confirm => 'confirm',
      };
  int get index1 => ReturnStep.values.indexOf(this) + 1;
}

class ReturnFlowState {
  const ReturnFlowState({
    this.step = ReturnStep.items,
    this.selected = const {},
    this.reasons = const {},
    this.notes = const {},
    this.submitting = false,
    this.createdReturnId,
    this.createdShipping,
    this.error,
  });

  final ReturnStep step;
  final Map<int, int> selected; // orderItemId -> quantity
  final Map<int, String> reasons; // orderItemId -> reason code
  final Map<int, String> notes; // orderItemId -> free-text note
  final bool submitting;
  final int? createdReturnId;

  /// RT-02: the created return's cargo code + carrier (for the confirm step).
  final ReturnShippingDto? createdShipping;
  final String? error;

  bool get hasSelection => selected.isNotEmpty;
  bool get allReasonsSet =>
      selected.keys.every((id) => (reasons[id] ?? '').isNotEmpty);

  ReturnFlowState copyWith({
    ReturnStep? step,
    Map<int, int>? selected,
    Map<int, String>? reasons,
    Map<int, String>? notes,
    bool? submitting,
    int? createdReturnId,
    ReturnShippingDto? createdShipping,
    String? error,
    bool clearError = false,
  }) =>
      ReturnFlowState(
        step: step ?? this.step,
        selected: selected ?? this.selected,
        reasons: reasons ?? this.reasons,
        notes: notes ?? this.notes,
        submitting: submitting ?? this.submitting,
        createdReturnId: createdReturnId ?? this.createdReturnId,
        createdShipping: createdShipping ?? this.createdShipping,
        error: clearError ? null : (error ?? this.error),
      );
}

final returnFlowProvider =
    NotifierProviderFamily<ReturnFlowNotifier, ReturnFlowState, int>(
  ReturnFlowNotifier.new,
);

/// Shape #1: build() returns a const default; all mutation happens in handlers.
class ReturnFlowNotifier extends FamilyNotifier<ReturnFlowState, int> {
  @override
  ReturnFlowState build(int arg) => const ReturnFlowState();

  void goTo(ReturnStep step) => state = state.copyWith(step: step);

  /// Toggles an item's inclusion; selecting defaults quantity to 1, deselecting
  /// also drops its reason + note (so step 2 stays consistent).
  void toggleItem(int orderItemId) {
    final selected = Map<int, int>.from(state.selected);
    final reasons = Map<int, String>.from(state.reasons);
    final notes = Map<int, String>.from(state.notes);
    if (selected.containsKey(orderItemId)) {
      selected.remove(orderItemId);
      reasons.remove(orderItemId);
      notes.remove(orderItemId);
    } else {
      selected[orderItemId] = 1;
    }
    state = state.copyWith(selected: selected, reasons: reasons, notes: notes);
  }

  void setQuantity(int orderItemId, int qty) {
    if (!state.selected.containsKey(orderItemId) || qty < 1) return;
    final selected = Map<int, int>.from(state.selected)..[orderItemId] = qty;
    state = state.copyWith(selected: selected);
  }

  void setReason(int orderItemId, String reason) {
    final reasons = Map<int, String>.from(state.reasons)..[orderItemId] = reason;
    state = state.copyWith(reasons: reasons);
  }

  void setNote(int orderItemId, String note) {
    final notes = Map<int, String>.from(state.notes)..[orderItemId] = note;
    state = state.copyWith(notes: notes);
  }

  /// Builds the POST body from the current selection. RT-05: each line carries
  /// its own reason + note; the header reason stays the first item's (backward
  /// compat with the single-reason contract + the list/header view).
  CreateReturnRequest buildRequest(int orderId) {
    final items = [
      for (final entry in state.selected.entries)
        ReturnItemDto(
          orderItemId: entry.key,
          quantity: entry.value,
          reason: state.reasons[entry.key],
          note: state.notes[entry.key] ?? '',
        ),
    ];
    final firstId = state.selected.keys.first;
    final reason = state.reasons[firstId] ?? ReturnReason.other;
    // Backward-compat header description = the per-item notes folded together
    // (RT-05 also carries them per-line). #223 dropped this fold, silently
    // emptying the header description; restored.
    final description = state.notes.values.where((n) => n.isNotEmpty).join(' · ');
    return CreateReturnRequest(
      orderId: orderId,
      reason: reason,
      description: description,
      items: items,
    );
  }

  Future<void> submit(int orderId) async {
    if (!state.hasSelection || !state.allReasonsSet || state.submitting) return;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final repo = ref.read(orderRepositoryProvider);
      final created = await repo.createReturn(buildRequest(orderId));
      state = state.copyWith(
        submitting: false,
        createdReturnId: created.id,
        createdShipping: created.shipping,
        step: ReturnStep.confirm,
      );
    } catch (_) {
      state = state.copyWith(submitting: false, error: 'returns.cancel_error_generic');
    }
  }
}
