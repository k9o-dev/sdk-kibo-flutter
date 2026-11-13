import 'dart:convert';

/// Closed error taxonomy for K9O Kibo (vault) SDK operations.
/// Maps the gateway KError wire codes to Dart exception subclasses.
///
/// Same shape as `GateError` in `package:k9o_gate`: a per-package, closed
/// exception taxonomy over the platform error's `code`/`message` fields.
sealed class KiboError implements Exception {
  const KiboError();

  /// Session token missing, expired, or revoked (HTTP 401).
  const factory KiboError.unauthenticated() = _Unauthenticated;

  /// Caller lacks permission for the requested operation (HTTP 403).
  const factory KiboError.forbidden() = _Forbidden;

  /// `K9O_REVEAL_CHALLENGE_REQUIRED` — a valid single-use challenge (from
  /// `revealChallenge()`) is required but missing/invalid/expired on a `reveal()` call.
  const factory KiboError.revealChallengeRequired() = _RevealChallengeRequired;

  /// `K9O_INVALID_FIELD_VALUE` — a request field failed gateway-side validation.
  const factory KiboError.invalidFieldValue(String message) =
      _InvalidFieldValue;

  /// `K9O_NOT_FOUND` (HTTP 404) — no secret exists at that name. Also thrown by
  /// `VaultSecrets.get` when the exact name is not in the list.
  const factory KiboError.notFound(String message) = _NotFound;

  /// Transport-level failure — network unreachable, timeout, etc.
  const factory KiboError.network(Object cause) = _NetworkError;

  /// Gateway response could not be parsed into the expected shape.
  const factory KiboError.decoding(Object cause) = _DecodingError;

  /// Any other non-2xx HTTP status not covered above.
  const factory KiboError.unknown(int statusCode, String? body) = _UnknownError;
}

final class _Unauthenticated extends KiboError {
  const _Unauthenticated();
  @override
  String toString() =>
      'KiboError.unauthenticated: Session expired or not authenticated.';
}

final class _Forbidden extends KiboError {
  const _Forbidden();
  @override
  String toString() =>
      'KiboError.forbidden: Access forbidden for the current session.';
}

final class _RevealChallengeRequired extends KiboError {
  const _RevealChallengeRequired();
  @override
  String toString() =>
      'KiboError.revealChallengeRequired: A valid reveal challenge is required.';
}

final class _InvalidFieldValue extends KiboError {
  final String message;
  const _InvalidFieldValue(this.message);
  @override
  String toString() => 'KiboError.invalidFieldValue: $message';
}

final class _NotFound extends KiboError {
  final String message;
  const _NotFound(this.message);
  @override
  String toString() => 'KiboError.notFound: $message';
}

final class _NetworkError extends KiboError {
  final Object cause;
  const _NetworkError(this.cause);
  @override
  String toString() => 'KiboError.network: $cause';
}

final class _DecodingError extends KiboError {
  final Object cause;
  const _DecodingError(this.cause);
  @override
  String toString() => 'KiboError.decoding: $cause';
}

final class _UnknownError extends KiboError {
  final int statusCode;
  final String? body;
  const _UnknownError(this.statusCode, this.body);
  @override
  String toString() =>
      'KiboError.unknown: HTTP $statusCode — ${body ?? '<no body>'}';
}

// MARK: — Wire error parsing

/// Parse a non-2xx gateway response body into a [KiboError].
KiboError kiboErrorFromResponse(int statusCode, String? body) {
  if (body != null && body.isNotEmpty) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;
      // The gateway emits a KError at the ROOT: { code, message, … }
      // with K9O_-prefixed codes — NOT wrapped in { error: … }. Strip the
      // prefix to match the typed cases (same convention as `GateError`).
      final rawCode = json['code'] as String?;
      final code = (rawCode != null && rawCode.startsWith('K9O_'))
          ? rawCode.substring(4)
          : rawCode;
      final message = json['message'] as String? ?? 'Error';
      switch (code) {
        case 'UNAUTHENTICATED':
        case 'SESSION_EXPIRED':
        case 'MISSING_TOKEN':
          return const KiboError.unauthenticated();
        case 'FORBIDDEN':
          return const KiboError.forbidden();
        case 'REVEAL_CHALLENGE_REQUIRED':
          return const KiboError.revealChallengeRequired();
        case 'INVALID_FIELD_VALUE':
          return KiboError.invalidFieldValue(message);
        case 'NOT_FOUND':
          return KiboError.notFound(message);
      }
    } catch (_) {
      // Fall through to unknown() below — an unparsable body still surfaces
      // the raw statusCode/body rather than swallowing the failure.
    }
  }
  return KiboError.unknown(statusCode, body);
}
