import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:mopro/features/payments/sipay_error_map.dart';

const _pollIntervalMs = 1500;
const _timeoutMs = 30000;
const _msgCycleMs = 3000;

const _loadingMessages = [
  'Ödemen onaylanıyor…',
  'Bankadan onay bekleniyor…',
  'Neredeyse hazır…',
  'İşleminiz tamamlanıyor…',
];

const _terminalStatuses = {'captured', 'failed', 'cancelled', 'refunded'};

class CheckoutRedirectScreen extends ConsumerStatefulWidget {
  const CheckoutRedirectScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  ConsumerState<CheckoutRedirectScreen> createState() =>
      _CheckoutRedirectScreenState();
}

class _CheckoutRedirectScreenState
    extends ConsumerState<CheckoutRedirectScreen> {
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  Timer? _cycleTimer;

  int _msgIndex = 0;
  bool _timedOut = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: _pollIntervalMs),
      _poll,
    );
    _timeoutTimer = Timer(
      const Duration(milliseconds: _timeoutMs),
      _onTimeout,
    );
    _cycleTimer = Timer.periodic(
      const Duration(milliseconds: _msgCycleMs),
      (_) => setState(() => _msgIndex = (_msgIndex + 1) % _loadingMessages.length),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _cycleTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll(Timer timer) async {
    if (_done) return;
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get<Map<String, dynamic>>(
        '/payments/${widget.invoiceId}/intent-status',
      );
      final status = resp.data?['status'] as String? ?? 'pending';
      if (_terminalStatuses.contains(status)) {
        _done = true;
        timer.cancel();
        _timeoutTimer?.cancel();
        _cycleTimer?.cancel();
        if (!mounted) return;
        if (status == 'captured') {
          final orderId = resp.data?['order_id'];
          ref.read(checkoutControllerProvider.notifier).reset();
          context.go('/orders/$orderId');
        } else {
          final reason = resp.data?['failure_reason'] as String?;
          ref.read(checkoutControllerProvider.notifier).setPaymentError(
            SipayErrorMap.get(reason),
          );
          context.go('/checkout/review');
        }
      }
    } catch (_) {
      // swallow transient errors; keep polling
    }
  }

  void _onTimeout() {
    if (_done) return;
    _done = true;
    _pollTimer?.cancel();
    _cycleTimer?.cancel();
    if (mounted) setState(() => _timedOut = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_timedOut) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_bottom_outlined, size: 64, color: cs.tertiary),
                const SizedBox(height: 24),
                Text(
                  'Onay biraz gecikiyor',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Ödemeniz işleniyor olabilir. Siparişlerim sayfasını kontrol edin.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => context.go('/orders'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Siparişlerime Git'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Alışverişe Devam Et'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  _loadingMessages[_msgIndex],
                  key: ValueKey(_msgIndex),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
