# MenubarTranslate

[日本語](./README.ja.md)

A **local-only** macOS menu bar translation app. Japanese ↔ English, running
entirely on-device on Apple Silicon — no translation traffic leaves your machine.

## Status

Working. The residency/translation core, both inference engines (llama.cpp GGUF
and MLX), the `mbt` console tool and the SwiftUI menu-bar app are implemented and
covered by the test suite.

```bash
swift build
swift test
swift run mbt --dir ja-en "こんにちは"          # console
swift run MenubarTranslateApp                  # menu-bar app
```

The menu-bar app can listen on **loopback** `http://127.0.0.1:18787/` (override
`MBT_HTTP_PORT`) for [Immersive Translate](https://immersivetranslate.com/en/docs/services/custom/)
Custom API. Turn on **HTTP Loopback** in the gear menu. Enable Beta features in
the extension, pick Custom API, set that URL. Pairs are ja / en / zh only.

The real engines need local weights (`MBT_LLAMA_GGUF` / `MBT_MLX_DIR`) and, for
`--engine llama`, one run of `./scripts/build-llama-xcframework.sh`. Without
them `--engine fake` still exercises the whole residency path, and the
weight-gated tests skip rather than fail.

## Design at a glance

- **Model**: TranslateGemma-4B, GGUF `Q4_K_M` (~2.5 GB on disk, ~3–3.5 GB resident),
  on a llama.cpp / Metal runtime — the default, chosen by measurement. MLX 4-bit is
  the alternate (`--engine mlx`). See `docs/decisions/0008-runtime-selection-measured.md`
  (supersedes ADR 0001).
- **Memory target**: 8 GB unified memory first; 16 GB+ gets more permissive residency.
- **Residency**: the process stays alive; only model weights are evicted and reloaded
  ("weight-level residency"), amortising Metal/runtime init. Cold reload ≈ 0.5 s.
- **Eviction**: driven by idle timeout ∨ memory pressure. 8 GB evicts by default;
  16 GB residency is opt-in.
- **No thrash**: eviction reacts to pressure/timeout, loading reacts only to user
  intent — the asymmetry removes evict↔load oscillation, backed by double hysteresis.
- **Under `Critical` pressure**: lean-load + evict-after-use, plus a capability-gated
  fallback to Apple's on-device Translation framework.

Full record: `docs/architecture.md`, the ADRs in `docs/decisions/`, and open
measurement tasks in `docs/validation.md`.

## Conventions

This repo follows the `penta2himajin/templates` conventions: SSOT in `AGENTS.md`
(`CLAUDE.md` is a symlink), ADRs in `docs/decisions/`, issue-based session handoff
(`docs/handoff-protocol.md`), and English-only engineering docs (`docs/i18n-policy.md`).

## License

MIT. See `LICENSE`.
