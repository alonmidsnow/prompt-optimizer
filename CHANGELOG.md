# Changelog

## 0.6.0-beta.1 — 2026-10-17

First open-source preparation, based on the existing local helper.

- MIT license, original Swift source and checks, public configuration template and privacy/contribution/release documents.
- Accept drag installation into `/Applications` as well as the current user's `~/Applications`; retain single-instance protection.
- Build ZIP and DMG with macOS tools. Include MIT license, remove debug source paths before signing, and generate a relative-path SHA-256 file.
- Provide a read-only macOS CI template for builds and checks; it is not enabled in this release. No automatic credential use or release publishing.
- Keep desktop scope explicit: Codex desktop and Claude desktop Code mode. Terminal editing is not currently supported.

Existing features include floating optimization, in-memory originals, native undo compatibility, progress/completion states and an explicit choice of Codex CLI or OpenAI-compatible API. The removed dedicated Restore button is not reintroduced.

This prerelease is not Apple-notarized. Current downloadable build is arm64; other machines, native undo, full visual behavior and real third-party API services still require acceptance testing.
