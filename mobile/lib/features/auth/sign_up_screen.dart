import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/layout/auth_layout.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/auth/auth_signup_notifier.dart';
import 'package:mopro/features/auth/auth_widgets.dart';


class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _passwordValue = '';

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signUpNotifierProvider);
    final notifier = ref.read(signUpNotifierProvider.notifier);

    ref.listen<SignUpState>(signUpNotifierProvider, (_, next) {
      if (next.registered) {
        context.go(
          '/auth/verify-email',
          extra: _emailCtrl.text.trim(),
        );
      }
    });

    return AuthLayout(
      showBackButton: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hesap Oluştur',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Birkaç dakikada ücretsiz kayıt olun',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthFieldLabel('Ad'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _firstCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: authInputDecoration(
                          context,
                          hint: 'Adınız',
                          prefixIcon: Icons.person_outline,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Zorunlu' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthFieldLabel('Soyad'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _lastCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: authInputDecoration(
                          context,
                          hint: 'Soyadınız',
                          prefixIcon: Icons.person_outline,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Zorunlu' : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const AuthFieldLabel('E-posta'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
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
            const AuthFieldLabel('Parola'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (v) => setState(() => _passwordValue = v),
              decoration: authInputDecoration(
                context,
                hint: 'En az 8 karakter',
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
              validator: (v) => PasswordStrengthIndicator.isStrong(v ?? '')
                  ? null
                  : 'Parola güçlü değil',
            ),
            if (_passwordValue.isNotEmpty) ...[
              const SizedBox(height: 10),
              PasswordStrengthIndicator(password: _passwordValue),
            ],
            const SizedBox(height: 16),
            const AuthFieldLabel('Parola Tekrar'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(notifier),
              decoration: authInputDecoration(
                context,
                hint: 'Parolayı tekrar girin',
                prefixIcon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) =>
                  v != _passwordCtrl.text ? 'Parolalar eşleşmiyor' : null,
            ),
            if (state.error != null) ...[
              const SizedBox(height: 16),
              AuthErrorBanner(message: _errorMessage(state.error!)),
            ],
            const SizedBox(height: 24),
            AuthSubmitButton(
              isLoading: state.isLoading,
              label: 'Kayıt Ol',
              onPressed: () => _submit(notifier),
            ),
            const SizedBox(height: 32),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Zaten hesabın var mı? ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/auth/login'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Giriş yap',
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

  void _submit(SignUpNotifier notifier) {
    if (!_formKey.currentState!.validate()) return;
    notifier.submit(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      nameFirst: _firstCtrl.text.trim(),
      nameLast: _lastCtrl.text.trim(),
    );
  }

  String _errorMessage(AppError error) => switch (error) {
        EmailAlreadyExistsError() =>
          'Bu e-posta adresi zaten kayıtlı. Giriş yapmayı deneyin.',
        WeakPasswordError() => 'Parola en az 8 karakter olmalıdır.',
        NetworkError() =>
          'Bağlantı hatası. İnternet bağlantınızı kontrol edin.',
        _ => 'Bir hata oluştu. Lütfen tekrar deneyin.',
      };
}
