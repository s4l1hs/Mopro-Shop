import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/auth/auth_widgets.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _mfaEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get<Map<String, dynamic>>('/me');
      final data = resp.data;
      if (mounted) {
        setState(() => _mfaEnabled = data?['mfa_enabled'] == true);
      }
    } catch (_) {
      // best-effort; defaults to false
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('account.security'.tr())),
      backgroundColor: cs.surfaceContainerHighest,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _SectionLabel('security.section_password'.tr()),
                _RowCard(
                  icon: Icons.lock_outline_rounded,
                  title: 'security.change_password_title'.tr(),
                  subtitle: 'security.change_password_sub'.tr(),
                  onTap: () => _showChangePasswordSheet(context),
                ),
                _SectionLabel('security.section_mfa'.tr()),
                _RowCard(
                  icon: _mfaEnabled
                      ? Icons.verified_user_rounded
                      : Icons.shield_outlined,
                  title: _mfaEnabled
                      ? 'security.mfa_active_title'.tr()
                      : 'security.mfa_enable_title'.tr(),
                  subtitle: _mfaEnabled
                      ? 'security.mfa_active_sub'.tr()
                      : 'security.mfa_inactive_sub'.tr(),
                  iconColor: _mfaEnabled ? Colors.green : cs.primary,
                  onTap: () => _mfaEnabled
                      ? _showDisableMfa(context)
                      : _showEnrollMfa(context),
                ),
              ],
            ),
    );
  }

  Future<void> _showChangePasswordSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  Future<void> _showEnrollMfa(BuildContext context) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _EnrollMfaSheet(),
    );
    if ((ok ?? false) && mounted) {
      setState(() => _mfaEnabled = true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('security.mfa_enabled_toast'.tr())),
      );
    }
  }

  Future<void> _showDisableMfa(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('security.mfa_disable_title'.tr()),
        content: Text('security.mfa_disable_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('security.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('security.disable'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.delete<void>('/auth/mfa');
      if (mounted) {
        setState(() => _mfaEnabled = false);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('security.mfa_disabled_toast'.tr())),
        );
      }
    } on DioException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'security.error_generic'.tr(
              namedArgs: {'msg': e.message ?? 'security.unknown'.tr()},
            ),
          ),
        ),
      );
    }
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();
  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _submitting = false;
  String _newValue = '';
  String? _error;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.post<void>('/me/password', data: {
        'old_password': _oldCtrl.text,
        'new_password': _newCtrl.text,
      },);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('security.password_updated_toast'.tr())),
        );
      }
    } on DioException catch (e) {
      final code = (e.response?.data is Map)
          ? (e.response?.data as Map)['error']?.toString()
          : null;
      setState(() {
        if (code == 'invalid_credentials') {
          _error = 'security.current_password_wrong'.tr();
        } else if (code == 'weak_password') {
          _error = 'security.new_password_invalid'.tr();
        } else {
          _error = 'security.generic_error'.tr();
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'security.change_password_title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                AuthFieldLabel('security.current_password_label'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _oldCtrl,
                  obscureText: _obscureOld,
                  decoration: authInputDecoration(
                    context,
                    hint: '••••••••',
                    prefixIcon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureOld
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,),
                      onPressed: () =>
                          setState(() => _obscureOld = !_obscureOld),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'auth.sign_up.required'.tr() : null,
                ),
                const SizedBox(height: 12),
                AuthFieldLabel('security.new_password_label'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _newCtrl,
                  obscureText: _obscureNew,
                  onChanged: (v) => setState(() => _newValue = v),
                  decoration: authInputDecoration(
                    context,
                    hint: 'auth.sign_up.password_hint'.tr(),
                    prefixIcon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  validator: (v) =>
                      PasswordStrengthIndicator.isStrong(v ?? '')
                          ? null
                          : 'security.strong_password_required'.tr(),
                ),
                if (_newValue.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  PasswordStrengthIndicator(password: _newValue),
                ],
                const SizedBox(height: 12),
                AuthFieldLabel('security.new_password_confirm_label'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureNew,
                  decoration: authInputDecoration(
                    context,
                    hint: 'security.password_confirm_hint'.tr(),
                    prefixIcon: Icons.lock_outline,
                  ),
                  validator: (v) =>
                      v != _newCtrl.text ? 'auth.sign_up.password_mismatch'.tr() : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  AuthErrorBanner(message: _error!),
                ],
                const SizedBox(height: 20),
                AuthSubmitButton(
                  isLoading: _submitting,
                  label: 'security.update_password'.tr(),
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnrollMfaSheet extends ConsumerStatefulWidget {
  const _EnrollMfaSheet();
  @override
  ConsumerState<_EnrollMfaSheet> createState() => _EnrollMfaSheetState();
}

class _EnrollMfaSheetState extends ConsumerState<_EnrollMfaSheet> {
  final _phoneCtrl = TextEditingController(text: '+90');
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (!RegExp(r'^\+\d{8,15}$').hasMatch(phone)) {
      setState(() => _error = 'security.phone_format_error'.tr());
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.post<void>('/auth/mfa/enroll', data: {'phone': phone});
      setState(() => _codeSent = true);
    } on DioException catch (e) {
      setState(() => _error = 'security.code_send_failed'.tr(
            namedArgs: {
              'status': e.response?.statusCode?.toString() ??
                  'security.connection_error'.tr(),
            },
          ),);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirm() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'security.code_length_error'.tr());
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.post<void>('/auth/mfa/confirm',
          data: {'phone': _phoneCtrl.text.trim(), 'code': code},);
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final body = e.response?.data;
      final errCode = body is Map ? body['error']?.toString() : null;
      setState(() {
        if (errCode == 'mfa_invalid' || errCode == 'otp_invalid') {
          _error = 'security.invalid_code'.tr();
        } else if (errCode == 'mfa_already_enabled') {
          _error = 'security.mfa_already_active'.tr();
        } else {
          _error = 'security.operation_failed'.tr();
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      color: MoproTokens.primaryLight, size: 24,),
                  const SizedBox(width: 8),
                  Text(
                    'security.mfa_enable_title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _codeSent
                    ? 'security.enroll_code_prompt'.tr()
                    : 'security.enroll_phone_prompt'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              if (!_codeSent) ...[
                AuthFieldLabel('security.phone_label'.tr()),
                const SizedBox(height: 6),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9+]')),
                  ],
                  decoration: authInputDecoration(
                    context,
                    hint: '+905551234567',
                    prefixIcon: Icons.phone_outlined,
                  ),
                ),
              ] else ...[
                AuthFieldLabel('security.code_label'.tr()),
                const SizedBox(height: 6),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                AuthErrorBanner(message: _error!),
              ],
              const SizedBox(height: 20),
              AuthSubmitButton(
                isLoading: _submitting,
                label: _codeSent
                    ? 'security.confirm'.tr()
                    : 'security.send_code'.tr(),
                onPressed: _codeSent ? _confirm : _sendCode,
              ),
              if (_codeSent) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _codeSent = false),
                  child: Text('security.change_phone'.tr()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: (iconColor ?? cs.primary).withAlpha(24),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor ?? cs.primary),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}
