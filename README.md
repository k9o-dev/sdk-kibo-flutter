# k9o_kibo

Official Flutter SDK for [Kilimanjaro](#84-about-kilimanjaro) Kibo.
Store, list and reveal secrets in the Kibo vault from your Flutter app.

## Contents

**A. Get started**

1. [Links](#1-links)
2. [Install](#2-install)
3. [Choose the right package](#3-choose-the-right-package)
4. [Requirements](#4-requirements)
5. [Quick start](#5-quick-start)

**B. Use Kibo**

6. [Behaviour to know about](#6-behaviour-to-know-about)

**C. Troubleshoot**

7. [Handle errors](#7-handle-errors)

**D. Reference**

8. [Appendix](#8-appendix)
   - 8.1 [Client options](#81-client-options)
   - 8.2 [Error fields](#82-error-fields)
   - 8.3 [Methods](#83-methods)
   - 8.4 [About Kilimanjaro](#84-about-kilimanjaro)
9. [License](#9-license)

## A. Get started

### 1. Links

- Website: <https://kilimanjaro.dev>
- Documentation / Developer Hub: <https://docs.kilimanjaro.dev>
- API: <https://api.k9o.io>
- Console: <https://console.k9o.io>
- Open source
  - Platform: <https://github.com/k9o-platform>
  - Community: <https://github.com/k9o-community>

### 2. Install

```bash
dart pub add k9o_kibo:^1.5.0
```

### 3. Choose the right package

| Package | Use it when you are… | Registry | Source |
| --- | --- | --- | --- |
| `k9o_core` | Calling the platform from a Flutter app as a signed-in user. | [pub.dev](https://pub.dev/packages/k9o_core) | [sdk-flutter](https://github.com/k9o-platform/sdk-flutter) |
| `k9o_gate` | Signing users in: sign in, refresh and sign out. | [pub.dev](https://pub.dev/packages/k9o_gate) | [sdk-flutter](https://github.com/k9o-platform/sdk-flutter) |
| `k9o_kibo` | Storing, listing and revealing secrets in the vault. | [pub.dev](https://pub.dev/packages/k9o_kibo) | [sdk-kibo-flutter](https://github.com/k9o-platform/sdk-kibo-flutter) |

### 4. Requirements

- Dart 3.0 or later
- Pure Dart: it also works in Flutter apps and on Dart servers

### 5. Quick start

The example uses a project called `my-project`, which belongs to the organization `acme`.

```dart
import 'package:k9o_kibo/k9o_kibo.dart';

final kibo = KiboClient(
  orgBaseUrl: 'https://acme.api.k9o.io',
  projectSlug: 'my-project',
);

await kibo.vault.secrets.create(name: 'db/pw', value: 'hunter2');

final challenge = await kibo.vault.secrets.revealChallenge('db/pw');
final revealed = await kibo.vault.secrets.reveal(
  'db/pw',
  challenge: challenge.challenge,
);

print(revealed.value);
```

```text
hunter2
```

Values are plaintext in your code. The SDK handles the wire encoding.

## B. Use Kibo

### 6. Behaviour to know about

- Reading a secret is a two-step flow: ask for a challenge, then reveal with it.
- `region` is optional on every named-secret method. It is sent only when you pass it.
- `get(name)` finds a secret by its exact name and returns its metadata, never its value.
- `get(name)` throws `KiboError.notFound` when no secret has that name.
- `update` returns `id`, `name` and `version`, not the full summary.
- `delete` succeeds on any 2xx response.
- The client adds no `Authorization` header. To authenticate, pass an `httpClient` that adds it.

## C. Troubleshoot

### 7. Handle errors

Every call throws a `KiboError`. Its `toString()` starts with the kind of error.

```dart
try {
  await kibo.vault.secrets.get('db/missing');
} on KiboError catch (error) {
  print(error);
}
```

```text
KiboError.notFound: No secret named 'db/missing' in this project.
```

See all [error cases](#82-error-fields).

## D. Reference

### 8. Appendix

- [Client options](#81-client-options)
- [Error fields](#82-error-fields)
- [Methods](#83-methods)
- [About Kilimanjaro](#84-about-kilimanjaro)

#### 8.1 Client options

`KiboClient(orgBaseUrl:, projectSlug:, httpClient:)`

| Option | Meaning |
|---|---|
| `orgBaseUrl` | Your organization's API host, for example `https://acme.api.k9o.io` |
| `projectSlug` | The project's slug |
| `httpClient` | A `package:http` `Client`; default is a new `Client` |

#### 8.2 Error fields

| Kind | Meaning |
|---|---|
| `KiboError.unauthenticated` | The session is missing, expired or revoked |
| `KiboError.forbidden` | The session may not perform this operation |
| `KiboError.revealChallengeRequired` | The reveal challenge is missing, invalid or expired |
| `KiboError.invalidFieldValue` | A request field failed validation |
| `KiboError.notFound` | No secret has that name |
| `KiboError.network` | The request failed in transit |
| `KiboError.decoding` | The response was not in the expected shape |
| `KiboError.unknown` | Any other non-2xx response, with the status and raw body |

#### 8.3 Methods

All methods are on `kibo.vault.secrets`.

| Method | Meaning |
|---|---|
| `list({prefix, cursor, limit})` | List secret metadata; returns `ListSecretsResult` |
| `get(name)` | One secret's metadata, found by exact name; returns `SecretSummary` |
| `create({name, value, region, visibility, metadata})` | Create a secret; returns `SecretSummary` |
| `revealChallenge(name, {region, reason})` | Get a single-use challenge; `reason` is optional |
| `reveal(name, {region, challenge})` | Read the plaintext value; returns `RevealSecretResult` |
| `update(name, {region, value, metadata})` | Set a new value; returns `UpdateSecretResult` |
| `rotate(name, {region})` | Re-wrap the secret under a new key; returns `RotateSecretResult` |
| `move(name, {region, newPath})` | Change the secret's path; returns `MoveSecretResult` |
| `delete(name, {region})` | Retire the secret |

#### 8.4 About Kilimanjaro

Kilimanjaro is a modular developer platform for building secure enterprise applications.
You define AI agents, functions and data pipelines on the platform.
The SDKs let you deploy and invoke them, read and write your data, publish to and subscribe to streams, sign users in, and encrypt with keys you hold.

It provides four building blocks:

- **Keep**: AI security and governance. Guardrails and policy for the agents you run.
- **Pulse**: data intelligence and real-time stream processing. Streams, analytics and live feeds.
- **Gate**: customer identity and access management. Sign-in and sessions, and automatic data scoping so a signed-in user reaches only their own data.
- **Kibo**: cryptographic keys and secrets management. Client-side encryption with keys you hold, and a secrets vault.

### 9. License

Apache-2.0 © Formelo Inc. See `LICENSE` and `NOTICE`.
