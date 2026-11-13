# k9o_kibo Flutter SDK — Changelog

## 1.5.0 (unreleased)

### Changed

- README description.

## 1.3.0 — 2026-10-26

### Changed

- `get(name)` finds the secret by its exact name through the list route and throws `KiboError.notFound` when it is absent. It used to always fail.
- `region` is optional on every named-secret method and is sent only when you pass it.
- `delete` accepts any 2xx response.
- Response fields are read as the gateway sends them (camelCase).

### Added

- `KiboError.notFound`.
- `revealChallenge(name, {region, reason})` takes an optional `reason`.

## 1.0.0 First public release

First public release. See the README for the full API overview.
