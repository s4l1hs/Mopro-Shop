import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/layout/auth_layout.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/auth/auth_signin_notifier.dart';
import 'package:mopro/features/auth/auth_widgets.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signInNotifierProvider);
    final notifier = ref.read(signInNotifierProvider.notifier);

    ref.listen<SignInState>(signInNotifierProvider, (_, next) {
      if (next.requiresMFA && next.mfaToken != null) {
        context.go('/auth/mfa', extra: {
          'mfa_token': next.mfaToken,
          'masked_phone': next.maskedPhone ?? '',
        });
      }
    });

    return AuthLayout(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Giriş Yap',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hesabınıza giriş yapın',
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
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const AuthFieldLabel('Parola'),
                TextButton(
                  onPressed: () => context.go('/auth/forgot-password'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Şifremi unuttum',
                    style: TextStyle(
                      color: MoproTokens.primaryLight,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(notifier),
              decoration: authInputDecoration(
                context,
                hint: '••••••••',
                prefixIcon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'En az 8 karakter girin' : null,
            ),
            if (state.error != null) ...[
              const SizedBox(height: 16),
              AuthErrorBanner(message: _errorMessage(state.error!)),
            ],
            const SizedBox(height: 24),
            AuthSubmitButton(
              isLoading: state.isLoading,
              label: 'Giriş Yap',
              onPressed: () => _submit(notifier),
            ),
            const SizedBox(height: 32),
            const AuthOrDivider(),
            const SizedBox(height: 24),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hesabın yok mu? ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/auth/register'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Kayıt ol',
                      style: TextStyle(
                        color: MoproTokens.primaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit(SignInNotifier notifier) {
    if (!_formKey.currentState!.validate()) return;
    notifier.submit(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
  }

  String _errorMessage(AppError error) => switch (error) {
        InvalidCredentialsError() => 'E-posta veya parola hatalı.',
        EmailNotVerifiedError() =>
          'E-posta adresiniz doğrulanmamış. Gelen kutunuzu kontrol edin.',
        RateLimitedError() => 'Çok fazla deneme. Lütfen biraz bekleyin.',
        NetworkError() =>
          'Bağlantı hatası. İnternet bağlantınızı kontrol edin.',
        _ => 'Bir hata oluştu. Lütfen tekrar deneyin.',
      };
}

// Kept in this file only; real shared version is AuthSubmitButton in auth_widgets.dart.
// TODO: remove after full migration
class _SubmitButton extends AuthSubmitButton {
  const _SubmitButton({
    required super.isLoading,
    required super.label,
    required super.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: MoproTokens.primaryLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator.adaptive(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
