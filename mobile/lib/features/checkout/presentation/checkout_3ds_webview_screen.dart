import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:webview_flutter/webview_flutter.dart';

class Checkout3dsWebviewScreen extends ConsumerStatefulWidget {
  const Checkout3dsWebviewScreen({super.key});

  @override
  ConsumerState<Checkout3dsWebviewScreen> createState() =>
      _Checkout3dsWebviewScreenState();
}

class _Checkout3dsWebviewScreenState
    extends ConsumerState<Checkout3dsWebviewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final html = ref
            .read(checkoutControllerProvider)
            .response
            ?.threeDsHtml ??
        '';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onNavigationRequest: _handleNavigation,
        ),
      )
      ..loadHtmlString(html);
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri != null) {
      final path = uri.path.toLowerCase();
      if (path.contains('success') || path.contains('callback')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/checkout/result');
        });
        return NavigationDecision.prevent;
      }
      if (path.contains('fail') || path.contains('error')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/checkout/result?failed=1');
        });
        return NavigationDecision.prevent;
      }
    }
    return NavigationDecision.navigate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('checkout.secure_payment'.tr()),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () {
              ref.read(checkoutControllerProvider.notifier).reset();
              context.go('/cart');
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
