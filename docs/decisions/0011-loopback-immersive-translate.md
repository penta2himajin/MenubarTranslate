# ADR 0011 — Loopback HTTP for Immersive Translate

- Status: Accepted
- Date: 2026-08-14
- Related: ADR 0010, prohibition #1 (local-only)

## Context

The menu-bar app already translates ja / en / zh on-device. Immersive Translate
(Edge / Chrome) can call a **Custom API**: `POST` JSON `{source_lang, target_lang,
text_list}` and expects `{translations: [{detected_source_lang, text}]}`.

ADR 0010 forbids an HTTP *client* in the shipping binary so model fetch cannot
silently become on-path network. That is a different shape from a **loopback
server**: the browser on the same Mac talks to `127.0.0.1`, and inference still
goes through `AppRuntime` / `NetworkGuard`.

## Decision

1. The menu-bar app can listen on **loopback only** (`NWParameters.requiredInterfaceType
   = .loopback`), default port **18787**, override `MBT_HTTP_PORT`. The listener is
   **off until** the user checks **HTTP Loopback** in the settings menu
   (`LoopbackPreference` / `httpLoopbackEnabled`).
2. Pairs are accepted only when `LanguagePair.isSupported` is true (ja / en / zh,
   including Immersive tags like `zh-CN`). Other pairs return HTTP 400.
3. No HTTP client is added. Translation traffic still does not leave the machine.

## Consequences

- Immersive Translate must point Custom API at `http://127.0.0.1:18787/` and the
  app must be running.
- Binding `0.0.0.0` is out of scope; do not "fix" LAN access by opening the port.

## Alternatives

- **OpenAI-compatible `/v1/chat/completions`.** Immersive can use that too; it is
  a larger surface than their Custom API. Rejected for now.
- **XPC / native messaging.** More correct IPC, but Immersive Translate speaks HTTP.
