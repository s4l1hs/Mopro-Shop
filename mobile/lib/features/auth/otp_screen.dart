import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/auth/auth_otp_notifier.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({required this.phone, super.key});

  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controllers =
      List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OtpState>(authOtpNotifierProvider(widget.phone), (prev, next) {
      if (next.verified && !(prev?.verified ?? false)) {
        context.go('/');
      }
    });

    final state = ref.watch(authOtpNotifierProvider(widget.phone));
    final notifier =
        ref.read(authOtpNotifierProvider(widget.phone).notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('auth.otp_title'.tr()),
        leading: BackButton(onPressed: () => context.go('/auth/phone')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'auth.otp_subtitle'.tr(args: [widget.phone]),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _OtpBox(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  hasError: state.error != null,
                  onChanged: (val) => _onBoxChanged(i, val, notifier),
                  onBackspace: () => _onBackspace(i),
                ),),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText(context, state.error!),
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: state.canSubmit ? notifier.submit : null,
                  child: state.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : Text('auth.verify'.tr()),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: state.resendCountdown > 0
                    ? Text(
                        'auth.resend_countdown'.tr(
                          args: [state.resendCountdown.toString()],
                        ),
                        style: theme.textTheme.bodySmall,
                      )
                    : TextButton(
                        onPressed: notifier.resend,
                        child: Text('auth.resend'.tr()),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onBoxChanged(
    int index,
    String value,
    AuthOtpNotifier notifier,
  ) {
    // Handle paste: value may be >1 character.
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      _applyPaste(digits, notifier);
      return;
    }
    if (digits.isEmpty) return;
    _controllers[index].text = digits;
    if (index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
    }
    _notifyCode(notifier);
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    } else {
      _controllers[index].clear();
    }
    _notifyCode(
      ref.read(authOtpNotifierProvider(widget.phone).notifier),
    );
  }

  void _applyPaste(String digits, AuthOtpNotifier notifier) {
    final limited = digits.substring(0, digits.length < 6 ? digits.length : 6);
    for (var i = 0; i < limited.length; i++) {
      _controllers[i].text = limited[i];
    }
    final nextFocus = limited.length < 6 ? limited.length : 5;
    _focusNodes[nextFocus].requestFocus();
    _notifyCode(notifier);
  }

  void _notifyCode(AuthOtpNotifier notifier) {
    final code = _controllers.map((c) => c.text).join();
    notifier.onCodeChanged(code);
  }

  String _errorText(BuildContext context, AppError error) {
    return switch (error) {
      OtpInvalidError() => 'auth.otp_invalid'.tr(),
      OtpExpiredError() => 'auth.otp_expired'.tr(),
      OtpExhaustedError() => 'auth.rate_limit'.tr(),
      PhoneLockedError() => 'auth.phone_locked'.tr(),
      NetworkError() => 'auth.network_error'.tr(),
      _ => 'auth.unknown_error'.tr(),
    };
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final void Function(String) onChanged;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 44,
      height: 56,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            onBackspace();
          }
        },
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          autofillHints: const [AutofillHints.oneTimeCode],
          style: theme.textTheme.headlineSmall,
          decoration: InputDecoration(
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline,
              ),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
