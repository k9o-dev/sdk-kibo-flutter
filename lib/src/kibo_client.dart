import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'kibo_error.dart';
import 'vault_namespace.dart';

/// Kilimanjaro Kibo (vault) SDK.
///
/// [KiboClient] is the entry point. `client.vault.secrets.*` is the typed
/// secrets surface over `/@<projectSlug>/vault/secrets`.
///
/// Example:
/// ```dart
/// final kibo = KiboClient(orgBaseUrl: 'https://acme.api.k9o.io', projectSlug: 'my-project');
/// final summary = await kibo.vault.secrets.create(
///   name: 'db/pw',
///   value: 'hunter2',
/// );
/// ```
class KiboClient {
  final String _orgBaseUrl;
  final String _projectSlug;
  final http.Client _httpClient;

  /// `client.vault.*` — see [VaultNamespace].
  late final VaultNamespace vault;

  KiboClient({
    required String orgBaseUrl,
    required String projectSlug,
    http.Client? httpClient,
  })  : _orgBaseUrl = orgBaseUrl.replaceAll(RegExp(r'/$'), ''),
        _projectSlug = projectSlug,
        _httpClient = httpClient ?? http.Client() {
    vault = VaultNamespace(this);
  }

  // MARK: - Internal transport (used by the `vault.*` namespace classes; not
  // part of the package's public API surface beyond this library).

  /// Builds a project-scoped URI: `<orgBaseUrl>/@<projectSlug>/<subPath>?<query>`.
  /// Null-valued query entries are dropped (so optional params, e.g. `list`'s
  /// `prefix`/`cursor`/`limit`, are omitted rather than sent as `"null"`).
  Uri buildUri(String subPath, Map<String, String?> query) {
    final cleanedQuery = <String, String>{
      for (final entry in query.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    final uri = Uri.parse('$_orgBaseUrl/@$_projectSlug/$subPath');
    return cleanedQuery.isEmpty
        ? uri
        : uri.replace(queryParameters: cleanedQuery);
  }

  /// Performs the HTTP call and returns the decoded `data` field of the
  /// envelope (`{data, meta}`), or `null` for a 204/empty body.
  /// Throws a [KiboError] on any transport, decoding, or non-2xx failure.
  Future<dynamic> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final mergedHeaders = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
      'User-Agent': 'k9o-kibo-flutter',
      if (body != null) HttpHeaders.contentTypeHeader: 'application/json',
      ...?headers,
    };
    final encodedBody = body != null ? jsonEncode(body) : null;

    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _httpClient.get(uri, headers: mergedHeaders);
          break;
        case 'POST':
          response = await _httpClient.post(uri,
              headers: mergedHeaders, body: encodedBody);
          break;
        case 'PUT':
          response = await _httpClient.put(uri,
              headers: mergedHeaders, body: encodedBody);
          break;
        case 'DELETE':
          response = await _httpClient.delete(uri, headers: mergedHeaders);
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }
    } on KiboError {
      rethrow;
    } catch (e) {
      throw KiboError.network(e);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.statusCode == 204 || response.body.isEmpty) return null;
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['data'];
      } catch (e) {
        throw KiboError.decoding(e);
      }
    }
    throw kiboErrorFromResponse(response.statusCode, response.body);
  }
}
