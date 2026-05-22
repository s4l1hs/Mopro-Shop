sealed class AuthState {
  const AuthState();
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated();
}

/// Token exists but user has not yet completed mandatory profile fields.
final class AuthProfileIncomplete extends AuthState {
  const AuthProfileIncomplete();
}
