import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/layout/auth_layout.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/auth/auth_widgets.dart';

class EmailVerifyScreen extends ConsumerStatefulWidget {
  const EmailVerifyScreen({required this.email, super.key});
  final String email;

  @override
  ConsumerState<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends ConsumerState<EmailVerifyScreen> {
  final _codeCtrl = TextEditingController();
  bool _isLoading = false;
  AppError? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length != 8) {
      setState(() => _error = const InvalidCodeError());
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(authApiExtProvider);
      final result = await api.verifyEmail(email: widget.email, code: code);
      await ref.read(authNotifierProvider.notifier).setAuthenticated(
            accessToken: result.accessToken!,
            refreshToken: result.refreshToken!,
            expiresIn: result.expiresIn ?? 900,
          );
      // Router redirect will navigate to home or profile completion.
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _error = e is AppError ? e : const InvalidCodeError();
      });
    }
  }

  Future<void> _resend() async {
    try {
      await ref
          .read(authApiExtProvider)
          .resendVerification(email: widget.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doğrulama kodu tekrar gönderildi.'),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
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
                color: const Color.fromARGB(26, 202, 78, 0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.mark_email_unread_outlined,
                color: MoproTokens.primaryLight,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'E-postanızı Doğrulayın',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
              children: [
                const TextSpan(text: '8 karakterlik doğrulama kodunu '),
                TextSpan(
                  text: widget.email,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: ' adresine gönderdik.'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const AuthFieldLabel('Doğrulama Kodu'),
          const SizedBox(height: 6),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'A3B7C2D8',
              hintStyle: const TextStyle(letterSpacing: 6, fontSize: 22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: MoproTokens.primaryLight, width: 2),
              ),
              errorText: _error != null ? _errorText() : null,
            ),
            onChanged: (v) {
              if (v.trim().length == 8) _verify();
            },
          ),
          const SizedBox(height: 24),
          AuthSubmitButton(
            isLoading: _isLoading,
            label: 'Doğrula',
            onPressed: _verify,
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: _resend,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Kodu tekrar gönder'),
            ),
          ),
        ],
      ),
    );
  }

  String _errorText() => switch (_error) {
        InvalidCodeError() => 'Hatalı kod. Lütfen tekrar deneyin.',
        MFAChallengeExpiredError() =>
          'Kodun süresi doldu. Yeni kod isteyin.',
        _ => 'Bir hata oluştu.',
      };
}
