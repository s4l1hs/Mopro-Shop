sealed class AppError implements Exception {
  const AppError();
}

final class UnauthorizedError extends AppError {
  const UnauthorizedError();
}

final class OtpExpiredError extends AppError {
  const OtpExpiredError();
}

final class StepUpRequiredError extends AppError {
  const StepUpRequiredError();
}

final class SystemReadOnlyError extends AppError {
  const SystemReadOnlyError();
}

final class NotFoundError extends AppError {
  const NotFoundError({required this.resource});
  final String resource;
}

final class ValidationError extends AppError {
  const ValidationError({required this.message, this.fields = const []});
  final String message;
  final List<FieldError> fields;
}

final class FieldError {
  const FieldError({required this.field, required this.message});
  final String field;
  final String message;
}

final class RateLimitedError extends AppError {
  const RateLimitedError({this.retryAfterSeconds});
  final int? retryAfterSeconds;
}

final class ConflictError extends AppError {
  const ConflictError({required this.message});
  final String message;
}

final class NetworkError extends AppError {
  const NetworkError({required this.message});
  final String message;
}

final class UnknownError extends AppError {
  const UnknownError({required this.statusCode, required this.message});
  final int statusCode;
  final String message;
}

final class OtpInvalidError extends AppError {
  const OtpInvalidError();
}

final class OtpExhaustedError extends AppError {
  const OtpExhaustedError();
}

final class PhoneLockedError extends AppError {
  const PhoneLockedError();
}

final class SessionRevokedError extends AppError {
  const SessionRevokedError();
}

final class EmailAlreadyExistsError extends AppError {
  const EmailAlreadyExistsError();
}

final class InvalidCredentialsError extends AppError {
  const InvalidCredentialsError();
}

final class EmailNotVerifiedError extends AppError {
  const EmailNotVerifiedError();
}

final class WeakPasswordError extends AppError {
  const WeakPasswordError();
}

final class InvalidCodeError extends AppError {
  const InvalidCodeError();
}

final class MFAChallengeExpiredError extends AppError {
  const MFAChallengeExpiredError();
}
