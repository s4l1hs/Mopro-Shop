import 'package:easy_localization/easy_localization.dart';
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
              'auth.sign_up.title'.tr(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'auth.sign_up.subtitle'.tr(),
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
                      AuthFieldLabel('auth.name_first'.tr()),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _firstCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: authInputDecoration(
                          context,
                          hint: 'auth.sign_up.name_first_hint'.tr(),
                          prefixIcon: Icons.person_outline,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'auth.sign_up.required'.tr()
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AuthFieldLabel('auth.name_last'.tr()),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _lastCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: authInputDecoration(
                          context,
                          hint: 'auth.sign_up.name_last_hint'.tr(),
                          prefixIcon: Icons.person_outline,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'auth.sign_up.required'.tr()
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AuthFieldLabel('auth.email_label'.tr()),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
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
            AuthFieldLabel('auth.password_label'.tr()),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (v) => setState(() => _passwordValue = v),
              decoration: authInputDecoration(
                context,
                hint: 'auth.sign_up.password_hint'.tr(),
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
                  : 'auth.sign_up.password_weak'.tr(),
            ),
            if (_passwordValue.isNotEmpty) ...[
              const SizedBox(height: 10),
              PasswordStrengthIndicator(password: _passwordValue),
            ],
            const SizedBox(height: 16),
            AuthFieldLabel('auth.sign_up.password_confirm_label'.tr()),
            const SizedBox(height: 6),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(notifier),
              decoration: authInputDecoration(
                context,
                hint: 'auth.sign_up.password_confirm_hint'.tr(),
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
              validator: (v) => v != _passwordCtrl.text
                  ? 'auth.sign_up.password_mismatch'.tr()
                  : null,
            ),
            if (state.error != null) ...[
              const SizedBox(height: 16),
              AuthErrorBanner(message: _errorMessage(state.error!)),
            ],
            const SizedBox(height: 24),
            AuthSubmitButton(
              isLoading: state.isLoading,
              label: 'auth.sign_up.submit'.tr(),
              onPressed: () => _submit(notifier),
            ),
            const SizedBox(height: 32),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'auth.sign_up.have_account'.tr(),
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
                      'auth.sign_up.login_link'.tr(),
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
        EmailAlreadyExistsError() => 'auth.sign_up.error_email_exists'.tr(),
        WeakPasswordError() => 'auth.sign_up.error_weak_password'.tr(),
        NetworkError() => 'auth.network_error'.tr(),
        _ => 'auth.unknown_error'.tr(),
      };
}
