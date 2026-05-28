import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/layout/auth_layout.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/auth/auth_mfa_notifier.dart';
import 'package:mopro/features/auth/auth_widgets.dart';


class MFAChallengeScreen extends ConsumerStatefulWidget {
  const MFAChallengeScreen({
    required this.mfaToken, required this.maskedPhone, super.key,
  });
  final String mfaToken;
  final String maskedPhone;

  @override
  ConsumerState<MFAChallengeScreen> createState() =>
      _MFAChallengeScreenState();
}

class _MFAChallengeScreenState extends ConsumerState<MFAChallengeScreen> {
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mfaNotifierProvider);
    final notifier = ref.read(mfaNotifierProvider.notifier);

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
                Icons.phone_android_outlined,
                color: MoproTokens.primaryLight,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'İki Faktörlü Doğrulama',
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
                const TextSpan(text: 'Kayıtlı telefonunuza ('),
                TextSpan(
                  text: widget.maskedPhone,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: ') 6 haneli bir kod gönderdik.'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const AuthFieldLabel('Doğrulama Kodu'),
          const SizedBox(height: 6),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              hintStyle: const TextStyle(letterSpacing: 8, fontSize: 24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: MoproTokens.primaryLight, width: 2),
              ),
            ),
            onChanged: (v) {
              if (v.length == 6) {
                notifier.verify(mfaToken: widget.mfaToken, code: v);
              }
            },
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            AuthErrorBanner(message: _errorMessage(state.error!)),
          ],
          const SizedBox(height: 24),
          AuthSubmitButton(
            isLoading: state.isLoading,
            label: 'Doğrula',
            onPressed: () => notifier.verify(
              mfaToken: widget.mfaToken,
              code: _codeCtrl.text.trim(),
            ),
          ),
        ],
      ),
    );
  }

  String _errorMessage(AppError error) => switch (error) {
        InvalidCodeError() => 'Hatalı kod. Lütfen tekrar deneyin.',
        MFAChallengeExpiredError() =>
          'Kodun süresi doldu. Lütfen yeniden giriş yapın.',
        RateLimitedError() => 'Çok fazla deneme. Lütfen bekleyin.',
        _ => 'Bir hata oluştu.',
      };
}
