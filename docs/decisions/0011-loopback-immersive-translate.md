# ADR 0011 — Loopback HTTP for browser extensions

- Status: Accepted (amended 2026-09-22)
- Date: 2026-08-14
- Related: ADR 0010, prohibition #1 (local-only)

## Context

The menu-bar app already translates ja / en / zh on-device. Browser extensions
need a local HTTP seam:

- Immersive Translate **Custom API**: `POST` JSON `{source_lang, target_lang,
  text_list}` → `{translations: [{detected_source_lang, text}]}`.
- KISS Translator and similar tools speak **OpenAI-compatible**
  `POST /v1/chat/completions` (and often `GET /v1/models`).

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
4. **Thin OpenAI chat facade** (amendment): on the same listener, expose
   - `GET /v1/models` — lists a single local id `menubartranslate`
   - `POST /v1/chat/completions` — translation-only adapter: extract target
     language and source text from chat prompts (Immersive `%%` batches and
     KISS concise / JSON-segment prompts), run `AppRuntime`, return
     `choices[0].message.content`. `stream: true` is answered as a **single-chunk
     SSE** body, not a full token stream.
   Immersive Custom API on `POST /` remains unchanged.

## Consequences

- Immersive Translate Custom API: `http://127.0.0.1:18787/`
- KISS / Ollama-style OpenAI clients: `http://127.0.0.1:18787/v1/chat/completions`
  (API key ignored; model name ignored except echoed). Prefer disabling
  aggregation or using KISS JSON batch prompts the facade understands.
- Binding `0.0.0.0` is out of scope; do not "fix" LAN access by opening the port.
- This is **not** a general chat LLM endpoint (no tools, vision, or free-form Q&A).

## Alternatives

- **OpenAI-compatible only / drop Immersive Custom.** Rejected: Immersive Custom
  remains the smaller, translation-native shape for that extension.
- **KISS native `{texts,from,to}` custom API.** Useful but KISS-specific; OpenAI
  covers more clients with one surface.
- **XPC / native messaging.** More correct IPC, but extensions speak HTTP.
