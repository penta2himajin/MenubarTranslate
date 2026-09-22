# KISS Translator ↔ MenubarTranslate (loopback OpenAI)

MenubarTranslate exposes a **translation-only** OpenAI-compatible facade on the
same loopback listener as Immersive Custom API (ADR 0011).

## App

1. Run MenubarTranslate (menu bar).
2. Gear → enable **HTTP Loopback** (port `18787`, or `MBT_HTTP_PORT`).

Smoke:

```bash
curl -s http://127.0.0.1:18787/v1/models | head
curl -s http://127.0.0.1:18787/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer local' \
  -d '{
    "model": "menubartranslate",
    "stream": false,
    "messages": [
      {
        "role": "user",
        "content": "Translate the following text into Japanese - 日本語. Output ONLY the translated text without any explanation:\nHello"
      }
    ]
  }'
```

## KISS Translator

1. Install [KISS Translator](https://github.com/fishjar/kiss-translator)
   (Chrome/Edge extension id `bdiifdefkgmcblbcghdlonllpjhhjgof`).
   Options: `chrome-extension://bdiifdefkgmcblbcghdlonllpjhhjgof/options.html`
2. Add / edit an **OpenAI** or **Ollama** style API (OpenAI-compatible adapter):
   - URL: `http://127.0.0.1:18787/v1/chat/completions`
   - Model list (optional): `http://127.0.0.1:18787/v1/models`
   - Key: any non-empty string (ignored)
   - Model: `menubartranslate` (or any name; echoed only)
3. Prefer **single-segment / concise** prompts first. JSON batch prompts that end
   with `[{"id":0,"text":"..."}]` are also supported.
4. If streaming misbehaves, set `stream: false` in the API options (the facade
   answers `stream: true` with a single SSE chunk).

Pairs: **ja / en / zh** only.
