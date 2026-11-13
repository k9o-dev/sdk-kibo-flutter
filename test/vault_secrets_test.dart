import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:k9o_kibo/k9o_kibo.dart';
import 'package:test/test.dart';

// MARK: - Test helpers
//
// Wire-shape tests for `client.vault.secrets.*`: URL/query/method/body for the
// full family (list/get/create/revealChallenge/reveal/update/rotate/move/
// delete), including:
//  - `region` optional on every call and sent only when given
//  - `get` lists by exact-name prefix (the route answers a plain GET only as a reveal)
//  - `value` base64-encoded on write, base64-decoded on reveal
//  - the `X-K9O-Reveal-Challenge` header on `reveal`
// No real network calls are made - every request is served by a MockClient.

const summaryJson = {
  'id': 'sec_abc',
  'name': 'db/pw',
  'ownerId': 'usr_1',
  'visibility': {'kind': 'private'},
  'version': 1,
  'kid': 'vkey_1',
  'createdAt': 't',
  'createdBy': 'usr_1',
  'updatedAt': 't',
  'updatedBy': 'usr_1',
  'rotatedAt': null,
  'retiredAt': null,
  'metadata': <String, String>{},
};

String envelope(Object? data) => jsonEncode({'data': data, 'meta': {}});

class CapturedRequest {
  String method = '';
  Uri? url;
  String? body;
  Map<String, String> headers = {};
}

KiboClient makeKibo({
  required CapturedRequest capture,
  required Object? responseData,
  int status = 200,
}) {
  final client = MockClient((req) async {
    capture.method = req.method;
    capture.url = req.url;
    capture.headers = req.headers;
    capture.body = req.body;
    if (status == 204) return http.Response('', 204);
    return http.Response(
      envelope(responseData),
      status,
      headers: {'content-type': 'application/json'},
    );
  });
  return KiboClient(
    orgBaseUrl: 'https://acme.api.k9o.io',
    projectSlug: 'member-portal',
    httpClient: client,
  );
}

void main() {
  group('vault.secrets', () {
    test(
        'list() GETs /@<slug>/vault/secrets with prefix/cursor/limit, no region',
        () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(
        capture: cap,
        responseData: {
          'secrets': [summaryJson],
          'nextCursor': null,
        },
      );
      final result = await kibo.vault.secrets.list(prefix: 'db/', limit: 10);
      expect(cap.method, 'GET');
      expect(
        cap.url.toString(),
        'https://acme.api.k9o.io/@member-portal/vault/secrets?prefix=db%2F&limit=10',
      );
      expect(result.secrets.single.id, 'sec_abc');
      expect(result.nextCursor, isNull);
    });

    test(
        'list() omits absent prefix/cursor/limit entirely (no "null" query values)',
        () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(
          capture: cap, responseData: {'secrets': [], 'nextCursor': null});
      await kibo.vault.secrets.list();
      expect(cap.url.toString(),
          'https://acme.api.k9o.io/@member-portal/vault/secrets');
    });

    test('get() lists by the exact name as prefix and returns the exact match',
        () async {
      final cap = CapturedRequest();
      final other = {...summaryJson, 'name': 'db/pw2', 'id': 'sec_other'};
      final kibo = makeKibo(capture: cap, responseData: {
        'secrets': [other, summaryJson],
        'nextCursor': null,
      });
      final result = await kibo.vault.secrets.get('db/pw');
      expect(cap.method, 'GET');
      expect(
        cap.url.toString(),
        'https://acme.api.k9o.io/@member-portal/vault/secrets?prefix=db%2Fpw&limit=100',
      );
      expect(cap.headers.containsKey('X-K9O-Reveal-Challenge'), isFalse);
      expect(result.id, 'sec_abc');
      expect(result.visibility, isA<SecretVisibility>());
    });

    test('get() throws KiboError.notFound when no secret has that name',
        () async {
      final cap = CapturedRequest();
      final other = {...summaryJson, 'name': 'db/pw2'};
      final kibo = makeKibo(capture: cap, responseData: {
        'secrets': [other],
        'nextCursor': null,
      });
      expect(() => kibo.vault.secrets.get('db/pw'),
          throwsA(isA<KiboError>().having((e) => e.toString(), 'string',
              contains('notFound'))));
    });

    test('create() without region sends no region query', () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(capture: cap, responseData: summaryJson);
      await kibo.vault.secrets.create(name: 'db/pw', value: 'hunter2');
      expect(cap.url.toString(),
          'https://acme.api.k9o.io/@member-portal/vault/secrets/db%2Fpw');
    });

    test('revealChallenge() with a reason sends {reason} and no region',
        () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(
        capture: cap,
        responseData: {'challenge': 'rvc_1', 'expiresAt': 't'},
      );
      await kibo.vault.secrets.revealChallenge('db/pw', reason: 'incident 42');
      expect(cap.method, 'POST');
      expect(cap.url.toString(),
          'https://acme.api.k9o.io/@member-portal/vault/secrets/db%2Fpw?op=reveal-challenge');
      expect(jsonDecode(cap.body!), {'reason': 'incident 42'});
    });

    test('delete() accepts a 200 with a body and sends no region when none given',
        () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(
          capture: cap, responseData: {'id': 'sec_abc', 'retiredAt': 't'});
      await kibo.vault.secrets.delete('db/pw');
      expect(cap.method, 'DELETE');
      expect(cap.url.toString(),
          'https://acme.api.k9o.io/@member-portal/vault/secrets/db%2Fpw');
    });

    test('create() POSTs with region query + base64-encoded value', () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(capture: cap, responseData: summaryJson);
      await kibo.vault.secrets.create(
        name: 'db/pw',
        value: 'hunter2',
        region: 'us01',
        visibility: const SecretVisibility.private(),
      );
      expect(cap.method, 'POST');
      expect(
        cap.url.toString(),
        'https://acme.api.k9o.io/@member-portal/vault/secrets/db%2Fpw?region=us01',
      );
      final body = jsonDecode(cap.body!) as Map<String, dynamic>;
      expect(body['value'], base64Encode(utf8.encode('hunter2')));
      expect(body['value'], isNot('hunter2'));
      expect(body['visibility'], {'kind': 'private'});
    });

    test('revealChallenge() POSTs ?op=reveal-challenge&region=<region>',
        () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(
        capture: cap,
        responseData: {'challenge': 'rvc_1', 'expiresAt': 't'},
      );
      final result = await kibo.vault.secrets
          .revealChallenge('db/pw', region: 'us01');
      expect(cap.method, 'POST');
      expect(cap.url.toString(), contains('op=reveal-challenge'));
      expect(cap.url.toString(), contains('region=us01'));
      expect(result.challenge, 'rvc_1');
    });

    test(
      'reveal() GETs with the X-K9O-Reveal-Challenge header and decodes base64 value to plaintext',
      () async {
        final cap = CapturedRequest();
        final wireValue = base64Encode(utf8.encode('hunter2'));
        final kibo = makeKibo(
          capture: cap,
          responseData: {
            'id': 'sec_abc',
            'name': 'db/pw',
            'version': 1,
            'value': wireValue,
            'revealedAt': 't',
            'attestationTier': {
              'urn': 'u',
              'operator': 'platform',
              'verified': true
            },
          },
        );
        final result = await kibo.vault.secrets.reveal(
          'db/pw',
          region: 'us01',
          challenge: 'rvc_1',
        );
        expect(cap.method, 'GET');
        expect(cap.headers['X-K9O-Reveal-Challenge'], 'rvc_1');
        expect(result.value, 'hunter2');
        expect(result.attestationTier.operator, 'platform');
      },
    );

    test(
      'update() PUTs with region query + base64-encoded value, returns the narrow {id,name,version} shape',
      () async {
        final cap = CapturedRequest();
        final kibo = makeKibo(
          capture: cap,
          responseData: {'id': 'sec_abc', 'name': 'db/pw', 'version': 2},
        );
        final result = await kibo.vault.secrets.update(
          'db/pw',
          region: 'us01',
          value: 'newpw',
        );
        expect(cap.method, 'PUT');
        expect(
          cap.url.toString(),
          'https://acme.api.k9o.io/@member-portal/vault/secrets/db%2Fpw?region=us01',
        );
        final body = jsonDecode(cap.body!) as Map<String, dynamic>;
        expect(body['value'], base64Encode(utf8.encode('newpw')));
        expect(result.version, 2);
      },
    );

    test('rotate() POSTs ?op=rotate&region=<region>, no body', () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(
        capture: cap,
        responseData: {
          'id': 'sec_abc',
          'name': 'db/pw',
          'version': 2,
          'rotatedAt': 't',
          'ledgerSequenceNumber': 2,
        },
      );
      final result =
          await kibo.vault.secrets.rotate('db/pw', region: 'us01');
      expect(cap.method, 'POST');
      expect(cap.url.toString(), contains('op=rotate'));
      expect(cap.body, isEmpty);
      expect(result.ledgerSequenceNumber, 2);
    });

    test('move() POSTs ?op=move&region=<region> with {newPath}', () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(
        capture: cap,
        responseData: {
          'id': 'sec_abc',
          'name': 'db/pw2',
          'event': 'SECRET_PATH_CHANGED'
        },
      );
      final result = await kibo.vault.secrets.move(
        'db/pw',
        region: 'us01',
        newPath: 'db/pw2',
      );
      expect(cap.method, 'POST');
      expect(cap.url.toString(), contains('op=move'));
      expect(jsonDecode(cap.body!), {'newPath': 'db/pw2'});
      expect(result.event, 'SECRET_PATH_CHANGED');
    });

    test('delete() DELETEs with region query and handles a 204 empty body',
        () async {
      final cap = CapturedRequest();
      final kibo = makeKibo(capture: cap, responseData: null, status: 204);
      await kibo.vault.secrets.delete('db/pw', region: 'us01');
      expect(cap.method, 'DELETE');
      expect(
        cap.url.toString(),
        'https://acme.api.k9o.io/@member-portal/vault/secrets/db%2Fpw?region=us01',
      );
    });
  });

  group('vault.secrets error mapping', () {
    test(
        'throws KiboError.revealChallengeRequired on K9O_REVEAL_CHALLENGE_REQUIRED',
        () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'K9O_REVEAL_CHALLENGE_REQUIRED',
            'message': 'challenge required',
            'context': {},
            'recommendation': null,
          }),
          400,
        ),
      );
      final kibo = KiboClient(
        orgBaseUrl: 'https://acme.api.k9o.io',
        projectSlug: 'member-portal',
        httpClient: client,
      );
      expect(
        () => kibo.vault.secrets.reveal('db/pw', challenge: 'stale'),
        throwsA(isA<KiboError>().having(
          (e) => e,
          'error',
          isA<KiboError>(),
        )),
      );
    });

    test(
        'throws KiboError.invalidFieldValue on K9O_INVALID_FIELD_VALUE',
        () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'K9O_INVALID_FIELD_VALUE',
            'message':
                'value rejected',
            'context': {},
            'recommendation': null,
          }),
          400,
        ),
      );
      final kibo = KiboClient(
        orgBaseUrl: 'https://acme.api.k9o.io',
        projectSlug: 'member-portal',
        httpClient: client,
      );
      try {
        await kibo.vault.secrets.rotate('db/pw', region: 'us01');
        fail('expected KiboError.invalidFieldValue');
      } on KiboError catch (e) {
        expect(e, isA<KiboError>());
        expect(e.toString(), contains('value rejected'));
      }
    });

    test('non-JSON 200 response throws KiboError.decoding', () async {
      final client = MockClient((_) async => http.Response('not-json', 200));
      final kibo = KiboClient(
        orgBaseUrl: 'https://acme.api.k9o.io',
        projectSlug: 'member-portal',
        httpClient: client,
      );
      expect(
        () => kibo.vault.secrets.list(),
        throwsA(isA<KiboError>()),
      );
    });

    test('500 response maps to KiboError.unknown', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'code': 'K9O_INTERNAL_ERROR', 'message': 'boom'}),
          500,
        ),
      );
      final kibo = KiboClient(
        orgBaseUrl: 'https://acme.api.k9o.io',
        projectSlug: 'member-portal',
        httpClient: client,
      );
      expect(
        () => kibo.vault.secrets.rotate('db/pw', region: 'us01'),
        throwsA(isA<KiboError>()),
      );
    });
  });
}
