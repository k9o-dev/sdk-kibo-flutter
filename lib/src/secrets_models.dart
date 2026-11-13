/// Model types for `client.vault.secrets.*`.
///
/// [UpdateSecretResult], [RotateSecretResult] and [MoveSecretResult] are typed
/// to what the gateway returns, not the OpenAPI `SecretSummary` shape.
library;

/// Secret visibility - write ops (create/update) stay owner-only regardless
/// of this tag. A tagged union via a sealed class + `kind` discriminator, matching
/// this package's existing style for closed taxonomies (see `KiboError`).
sealed class SecretVisibility {
  const SecretVisibility();

  const factory SecretVisibility.private() = _Private;

  const factory SecretVisibility.shared({
    List<String>? principals,
    List<String>? roles,
  }) = _Shared;

  factory SecretVisibility.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'private':
        return const SecretVisibility.private();
      case 'shared':
        return SecretVisibility.shared(
          principals: (json['principals'] as List<dynamic>?)?.cast<String>(),
          roles: (json['roles'] as List<dynamic>?)?.cast<String>(),
        );
      default:
        throw FormatException('Unknown SecretVisibility kind: $kind');
    }
  }

  Map<String, dynamic> toJson();
}

final class _Private extends SecretVisibility {
  const _Private();
  @override
  Map<String, dynamic> toJson() => const {'kind': 'private'};
}

final class _Shared extends SecretVisibility {
  final List<String>? principals;
  final List<String>? roles;
  const _Shared({this.principals, this.roles});
  @override
  Map<String, dynamic> toJson() => {
        'kind': 'shared',
        if (principals != null) 'principals': principals,
        if (roles != null) 'roles': roles,
      };
}

/// A secret WITHOUT its sealed ciphertext — the create/list/get metadata shape.
class SecretSummary {
  /// `sec_<base62>`.
  final String id;
  final String name;
  final String ownerId;
  final SecretVisibility visibility;
  final int version;

  /// The wrapping-key id at this version.
  final String kid;
  final String createdAt;
  final String createdBy;
  final String updatedAt;
  final String updatedBy;
  final String? rotatedAt;
  final String? retiredAt;
  final Map<String, String> metadata;

  const SecretSummary({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.visibility,
    required this.version,
    required this.kid,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.rotatedAt,
    this.retiredAt,
    required this.metadata,
  });

  factory SecretSummary.fromJson(Map<String, dynamic> json) => SecretSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        ownerId: json['ownerId'] as String,
        visibility: SecretVisibility.fromJson(
            json['visibility'] as Map<String, dynamic>),
        version: json['version'] as int,
        kid: json['kid'] as String,
        createdAt: json['createdAt'] as String,
        createdBy: json['createdBy'] as String,
        updatedAt: json['updatedAt'] as String,
        updatedBy: json['updatedBy'] as String,
        rotatedAt: json['rotatedAt'] as String?,
        retiredAt: json['retiredAt'] as String?,
        metadata:
            Map<String, String>.from(json['metadata'] as Map? ?? const {}),
      );
}

/// `list()` result.
class ListSecretsResult {
  final List<SecretSummary> secrets;
  final String? nextCursor;

  const ListSecretsResult({required this.secrets, this.nextCursor});

  factory ListSecretsResult.fromJson(Map<String, dynamic> json) =>
      ListSecretsResult(
        secrets: (json['secrets'] as List<dynamic>)
            .map((e) => SecretSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

/// `revealChallenge()` result — a single-use challenge to present on the
/// immediately-following `reveal()` call.
class RevealChallenge {
  final String challenge;
  final String expiresAt;

  const RevealChallenge({required this.challenge, required this.expiresAt});

  factory RevealChallenge.fromJson(Map<String, dynamic> json) =>
      RevealChallenge(
        challenge: json['challenge'] as String,
        expiresAt: json['expiresAt'] as String,
      );
}

/// The releasing node's observed attestation tier - present on every reveal.
class AttestationTier {
  /// `attestation:destination:region` trust-tier URN.
  final String urn;

  /// Node provenance: `platform` (Kibo-operated) or `client` (Private Perimeter).
  final String operator;

  /// Whether node attestation was verified against the vendor PKI on the URN's
  /// attestation segment.
  final bool verified;

  const AttestationTier({
    required this.urn,
    required this.operator,
    required this.verified,
  });

  factory AttestationTier.fromJson(Map<String, dynamic> json) =>
      AttestationTier(
        urn: json['urn'] as String,
        operator: json['operator'] as String,
        verified: json['verified'] as bool,
      );
}

/// `reveal()` result. `value` is the decoded plaintext — `VaultSecrets.reveal`
/// base64-decodes the wire value before constructing this (inverse of
/// `create`/`update`'s encode) — never the raw base64.
class RevealSecretResult {
  final String id;
  final String name;
  final int version;
  final String value;
  final String revealedAt;
  final AttestationTier attestationTier;

  const RevealSecretResult({
    required this.id,
    required this.name,
    required this.version,
    required this.value,
    required this.revealedAt,
    required this.attestationTier,
  });
}

/// `update()` result: the gateway returns only `{id, name, version}`, narrower
/// than the OpenAPI `SecretSummary`. Call `get()` afterward if the full summary
/// is needed.
class UpdateSecretResult {
  final String id;
  final String name;
  final int version;

  const UpdateSecretResult(
      {required this.id, required this.name, required this.version});

  factory UpdateSecretResult.fromJson(Map<String, dynamic> json) =>
      UpdateSecretResult(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as int,
      );
}

/// `rotate()` result: not described by the OpenAPI schema (which declares a
/// summary or a reveal challenge for the route); typed to what the gateway
/// returns. `ledgerSequenceNumber` is undocumented.
class RotateSecretResult {
  final String id;
  final String name;
  final int version;
  final String rotatedAt;
  final int ledgerSequenceNumber;

  const RotateSecretResult({
    required this.id,
    required this.name,
    required this.version,
    required this.rotatedAt,
    required this.ledgerSequenceNumber,
  });

  factory RotateSecretResult.fromJson(Map<String, dynamic> json) =>
      RotateSecretResult(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as int,
        rotatedAt: json['rotatedAt'] as String,
        ledgerSequenceNumber: json['ledgerSequenceNumber'] as int,
      );
}

/// `move()` result: not the OpenAPI `SecretSummary`; it has no `version` and
/// carries an undocumented `event` field (`"SECRET_PATH_CHANGED"` observed;
/// typed as `String`).
class MoveSecretResult {
  final String id;
  final String name;
  final String event;

  const MoveSecretResult(
      {required this.id, required this.name, required this.event});

  factory MoveSecretResult.fromJson(Map<String, dynamic> json) =>
      MoveSecretResult(
        id: json['id'] as String,
        name: json['name'] as String,
        event: json['event'] as String,
      );
}
