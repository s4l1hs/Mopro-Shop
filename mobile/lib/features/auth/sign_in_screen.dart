import 'package:easy_localization/easy_localization.dart';
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
        },);
      }
    });

    return AuthLayout(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'auth.login'.tr(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'auth.sign_in.subtitle'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),
            AuthFieldLabel('auth.email_label'.tr()),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: authInputDecoration(
                context,
                hint: 'auth.email_hint'.tr(),
                prefixIcon: Icons.email_outlined,
              ),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'auth.email_invalid'.tr()
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AuthFieldLabel('auth.password_label'.tr()),
                TextButton(
                  onPressed: () => context.go('/auth/forgot-password'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'auth.sign_in.forgot_password'.tr(),
                    style: const TextStyle(
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
              validator: (v) => (v == null || v.length < 8)
                  ? 'auth.sign_in.password_min'.tr()
                  : null,
            ),
            if (state.error != null) ...[
              const SizedBox(height: 16),
              AuthErrorBanner(message: _errorMessage(state.error!)),
            ],
            const SizedBox(height: 24),
            AuthSubmitButton(
              isLoading: state.isLoading,
              label: 'auth.login'.tr(),
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
                    'auth.sign_in.no_account'.tr(),
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
                      'auth.sign_in.register_link'.tr(),
                      style: const TextStyle(
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
        InvalidCredentialsError() =>
          'auth.sign_in.error_invalid_credentials'.tr(),
        EmailNotVerifiedError() =>
          'auth.sign_in.error_email_not_verified'.tr(),
        RateLimitedError() => 'auth.sign_in.error_rate_limited'.tr(),
        NetworkError() => 'auth.network_error'.tr(),
        _ => 'auth.unknown_error'.tr(),
      };
}
