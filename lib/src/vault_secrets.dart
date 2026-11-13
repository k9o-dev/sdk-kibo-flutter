import 'dart:convert';

import 'kibo_client.dart';
import 'kibo_error.dart';
import 'secrets_models.dart';

/// `client.vault.secrets.*`: the typed secrets surface over
/// `/@<projectSlug>/vault/secrets`: list / get / create / revealChallenge /
/// reveal / update / rotate / move / delete.
///
///  - `region` is optional on every named-secret method and sent only when
///    given: the gateway sets the residency region of each vault call itself and
///    discards a caller-supplied `region` query parameter (older gateways
///    required it).
///  - The wire `value` field is base64 in BOTH directions (a raw value is
///    rejected as unparseable). This class's public API always deals in
///    plaintext; base64 is purely a wire detail handled internally.
///  - `update`/`rotate`/`move` responses are typed to what the gateway returns,
///    not the OpenAPI `SecretSummary` shape - see `secrets_models.dart`.
class VaultSecrets {
  final KiboClient _client;

  VaultSecrets(this._client);

  /// UTF-8-safe base64 encode - the vault-secrets wire `value` field is base64
  /// (a raw, non-base64 `value` is rejected as unparseable).
  static String _encodeValue(String plaintext) =>
      base64Encode(utf8.encode(plaintext));

  /// Inverse of [_encodeValue] — decodes a revealed wire `value` back to plaintext.
  static String _decodeValue(String b64) => utf8.decode(base64Decode(b64));

  static String _secretPath(String name) =>
      'vault/secrets/${Uri.encodeComponent(name)}';

  /// List secrets (metadata only - never lists ciphertext).
  /// `GET /@<projectSlug>/vault/secrets`.
  Future<ListSecretsResult> list(
      {String? prefix, String? cursor, int? limit}) async {
    final uri = _client.buildUri('vault/secrets', {
      'prefix': prefix,
      'cursor': cursor,
      'limit': limit?.toString(),
    });
    final data = await _client.request('GET', uri) as Map<String, dynamic>;
    return ListSecretsResult.fromJson(data);
  }

  /// Read one secret's metadata (never its value - use [revealChallenge] +
  /// [reveal] for that).
  ///
  /// The gateway answers `GET /@<projectSlug>/vault/secrets/<name>` only as a
  /// reveal: with no `X-K9O-Reveal-Challenge` header it refuses with 401
  /// `K9O_REVEAL_CHALLENGE_REQUIRED`, whatever the caller's rights. There is no
  /// plain metadata read on that route, so this reads the metadata the route
  /// that exists for it returns: it lists by the exact name as prefix and picks
  /// the exact match. Throws [KiboError.notFound] when no secret has that name.
  Future<SecretSummary> get(String name) async {
    String? cursor;
    for (var page = 0; page < _maxGetPages; page++) {
      final result = await list(prefix: name, cursor: cursor, limit: 100);
      for (final s in result.secrets) {
        if (s.name == name) return s;
      }
      cursor = result.nextCursor;
      if (cursor == null) break;
    }
    throw KiboError.notFound("No secret named '$name' in this project.");
  }

  /// Bound on the pages [get] scans for an exact name.
  static const _maxGetPages = 20;

  /// Create a secret under the caller's own auth.
  /// `POST /@<projectSlug>/vault/secrets/<name>` -> the `sec_<base62>` summary.
  ///
  /// `value` is caller-facing plaintext; this method base64-encodes it for the
  /// wire. `region` is optional and discarded by the gateway.
  Future<SecretSummary> create({
    required String name,
    required String value,
    String? region,
    SecretVisibility? visibility,
    Map<String, String>? metadata,
  }) async {
    final uri = _client.buildUri(_secretPath(name), {'region': region});
    final body = <String, dynamic>{
      'value': _encodeValue(value),
      if (visibility != null) 'visibility': visibility.toJson(),
      if (metadata != null) 'metadata': metadata,
    };
    final data =
        await _client.request('POST', uri, body: body) as Map<String, dynamic>;
    return SecretSummary.fromJson(data);
  }

  /// Mint a single-use reveal challenge - present it as `X-K9O-Reveal-Challenge` on
  /// the immediately-following [reveal] call.
  /// `POST /@<projectSlug>/vault/secrets/<name>?op=reveal-challenge`. The optional
  /// [reason] is sent as `{reason}`; the gateway accepts it and does not forward
  /// it. With no reason there is no body.
  Future<RevealChallenge> revealChallenge(String name,
      {String? region, String? reason}) async {
    final uri = _client.buildUri(_secretPath(name), {
      'op': 'reveal-challenge',
      'region': region,
    });
    final data = await _client.request('POST', uri,
        body: reason != null ? {'reason': reason} : null) as Map<String, dynamic>;
    return RevealChallenge.fromJson(data);
  }

  /// Reveal a secret's plaintext value using a single-use challenge from
  /// [revealChallenge]. `GET /@<projectSlug>/vault/secrets/<name>`
  /// with `X-K9O-Reveal-Challenge`. Decodes the wire's base64 `value` back to
  /// plaintext (symmetric with [create]'s encode).
  Future<RevealSecretResult> reveal(
    String name, {
    String? region,
    required String challenge,
  }) async {
    final uri = _client.buildUri(_secretPath(name), {'region': region});
    final data = await _client.request(
      'GET',
      uri,
      headers: {'X-K9O-Reveal-Challenge': challenge},
    ) as Map<String, dynamic>;
    return RevealSecretResult(
      id: data['id'] as String,
      name: data['name'] as String,
      version: data['version'] as int,
      value: _decodeValue(data['value'] as String),
      revealedAt: data['revealedAt'] as String,
      attestationTier: AttestationTier.fromJson(
          data['attestationTier'] as Map<String, dynamic>),
    );
  }

  /// Update a secret's value (bumps version) - owner-only.
  /// `PUT /@<projectSlug>/vault/secrets/<name>`.
  ///
  /// Returns only `{id, name, version}` (see [UpdateSecretResult]); call [get]
  /// after if you need the rest.
  Future<UpdateSecretResult> update(
    String name, {
    String? region,
    required String value,
    Map<String, String>? metadata,
  }) async {
    final uri = _client.buildUri(_secretPath(name), {'region': region});
    final body = <String, dynamic>{
      'value': _encodeValue(value),
      if (metadata != null) 'metadata': metadata,
    };
    final data =
        await _client.request('PUT', uri, body: body) as Map<String, dynamic>;
    return UpdateSecretResult.fromJson(data);
  }

  /// Rotate a secret's wrapping key (re-wraps under a fresh `kid`; content
  /// unchanged) - owner-only.
  /// `POST /@<projectSlug>/vault/secrets/<name>?op=rotate`.
  Future<RotateSecretResult> rotate(String name, {String? region}) async {
    final uri =
        _client.buildUri(_secretPath(name), {'op': 'rotate', 'region': region});
    final data = await _client.request('POST', uri) as Map<String, dynamic>;
    return RotateSecretResult.fromJson(data);
  }

  /// Move (rename) a secret's hierarchical path - owner-only.
  /// `POST /@<projectSlug>/vault/secrets/<name>?op=move`.
  Future<MoveSecretResult> move(
    String name, {
    String? region,
    required String newPath,
  }) async {
    final uri =
        _client.buildUri(_secretPath(name), {'op': 'move', 'region': region});
    final data = await _client.request(
      'POST',
      uri,
      body: {'newPath': newPath},
    ) as Map<String, dynamic>;
    return MoveSecretResult.fromJson(data);
  }

  /// Retire a secret - owner-only.
  /// `DELETE /@<projectSlug>/vault/secrets/<name>`. Any 2xx is success (the
  /// gateway may answer `204 No Content` or `200` with a body; it is not read).
  Future<void> delete(String name, {String? region}) async {
    final uri = _client.buildUri(_secretPath(name), {'region': region});
    await _client.request('DELETE', uri);
  }
}
