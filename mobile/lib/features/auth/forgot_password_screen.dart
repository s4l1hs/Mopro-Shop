import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/layout/auth_layout.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/auth/auth_widgets.dart';
import 'package:mopro/features/auth/forgot_password_notifier.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(forgotPasswordNotifierProvider);
    final notifier = ref.read(forgotPasswordNotifierProvider.notifier);

    if (state.sent) {
      return AuthLayout(
        showBackButton: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Color.fromARGB(26, 202, 78, 0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  color: MoproTokens.primaryLight,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'E-posta Gönderildi',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Şifre sıfırlama bağlantısını e-posta adresinize gönderdik. '
              'Gelen kutunuzu kontrol edin.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),
            AuthSubmitButton(
              isLoading: false,
              label: 'Giriş sayfasına dön',
              onPressed: () => context.go('/auth/login'),
            ),
          ],
        ),
      );
    }

    return AuthLayout(
      showBackButton: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Şifremi Unuttum',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'E-posta adresinizi girin, şifre sıfırlama bağlantısı gönderelim.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),
            const AuthFieldLabel('E-posta'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(notifier),
              decoration: authInputDecoration(
                context,
                hint: 'ornek@email.com',
                prefixIcon: Icons.email_outlined,
              ),
              validator: (v) =>
                  (v == null || !v.contains('@'))
                      ? 'Geçerli bir e-posta girin'
                      : null,
            ),
            const SizedBox(height: 24),
            AuthSubmitButton(
              isLoading: state.isLoading,
              label: 'Bağlantı Gönder',
              onPressed: () => _submit(notifier),
            ),
          ],
        ),
      ),
    );
  }

  void _submit(ForgotPasswordNotifier notifier) {
    if (!_formKey.currentState!.validate()) return;
    notifier.submit(email: _emailCtrl.text.trim());
  }
}
