import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/core/network/app_error.dart';

/// Displays a dismissible error banner for [AppError] values.
/// Shows a localized message and an optional retry button.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    required this.error,
    this.onDismiss,
    this.onRetry,
    super.key,
  });

  final AppError error;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _message(error),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            if (onRetry != null) ...[
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('common.retry'.tr()),
              ),
              const SizedBox(width: 4),
            ],
            if (onDismiss != null)
              GestureDetector(
                onTap: onDismiss,
                child: Icon(
                  Icons.close,
                  color: theme.colorScheme.onErrorContainer,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _message(AppError error) {
    return switch (error) {
      SessionRevokedError() => 'auth.session_revoked'.tr(),
      OtpInvalidError() => 'auth.otp_invalid'.tr(),
      OtpExpiredError() => 'auth.otp_expired'.tr(),
      OtpExhaustedError() => 'auth.rate_limit'.tr(),
      PhoneLockedError() => 'auth.phone_locked'.tr(),
      UnauthorizedError() => 'error.unauthorized'.tr(),
      NetworkError() => 'auth.network_error'.tr(),
      RateLimitedError() => 'error.rate_limited'.tr(),
      SystemReadOnlyError() => 'error.system_read_only'.tr(),
      ValidationError() => 'error.validation'.tr(),
      NotFoundError() => 'error.not_found'.tr(args: [error.resource]),
      // Don't surface the raw backend message to the user (it's English server
      // text, e.g. a 409 stock/price conflict at checkout). Show clean, localized,
      // action-guiding copy; error.message is still kept on the object for logs.
      ConflictError() => 'error.conflict'.tr(),
      _ => 'auth.unknown_error'.tr(),
    };
  }
}
