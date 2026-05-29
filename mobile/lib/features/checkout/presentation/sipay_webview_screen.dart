import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ── Result types ──────────────────────────────────────────────────────────────

sealed class SipayResult {
  const SipayResult();

  factory SipayResult.fromParams(Map<String, String?> params) {
    final status = params['status'];
    final invoiceId = params['invoice_id'] ?? '';
    return switch (status) {
      'success' => SipayResultSuccess(invoiceId: invoiceId),
      'failed' => SipayResultFailed(
          reason: params['reason'] ?? params['error_code'] ?? 'payment_failed',
        ),
      'cancelled' => const SipayResultCancelled(),
      _ => SipayResultError(message: 'Bilinmeyen durum: $status'),
    };
  }
}

class SipayResultSuccess extends SipayResult {
  const SipayResultSuccess({required this.invoiceId});
  final String invoiceId;
}

class SipayResultFailed extends SipayResult {
  const SipayResultFailed({required this.reason});
  final String reason;
}

class SipayResultCancelled extends SipayResult {
  const SipayResultCancelled();
}

class SipayResultError extends SipayResult {
  const SipayResultError({required this.message});
  final String message;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class SipayWebViewScreen extends StatefulWidget {
  const SipayWebViewScreen({
    required this.url,
    required this.invoiceId,
    super.key,
  });

  final String url;
  final String invoiceId;

  @override
  State<SipayWebViewScreen> createState() => _SipayWebViewScreenState();
}

class _SipayWebViewScreenState extends State<SipayWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  static const String _returnScheme = 'mopro';
  static const String _returnHost = 'checkout';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (_) => setState(() => _isLoading = false),
          onNavigationRequest: _handleNavigation,
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    if (uri.scheme == _returnScheme && uri.host == _returnHost) {
      final result = SipayResult.fromParams(uri.queryParameters);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleResult(result);
      });
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  void _handleResult(SipayResult result) {
    switch (result) {
      case SipayResultSuccess(:final invoiceId):
        context.pushReplacement(
          '/checkout/redirect',
          extra: invoiceId,
        );
      case SipayResultFailed():
      case SipayResultError():
        Navigator.of(context).pop(result);
      case SipayResultCancelled():
        Navigator.of(context).pop(result);
    }
  }

  Future<bool> _confirmClose(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('checkout.cancel_payment_title'.tr()),
        content: Text('checkout.cancel_payment_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.no'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('common.yes'.tr()),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('checkout.secure_payment'.tr()),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () async {
              if (await _confirmClose(context)) {
                if (context.mounted) {
                  Navigator.of(context)
                      .pop(const SipayResultCancelled());
                }
              }
            },
            child: Text('common.cancel'.tr()),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
