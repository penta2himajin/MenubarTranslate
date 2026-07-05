# MenubarTranslate

[日本語](./README.ja.md)

A **local-only** macOS menu bar translation app. Japanese ↔ English, running
entirely on-device on Apple Silicon — no translation traffic leaves your machine.

## Status

Early design stage. No implementation yet. This repository currently holds the
working conventions (adopted from [`penta2himajin/templates`](https://github.com/penta2himajin/templates))
and the design record under `docs/`.

## Design at a glance

- **Model**: TranslateGemma-4B, GGUF `Q4_K_M` (~2.5 GB on disk, ~3–3.5 GB resident),
  on a llama.cpp / Metal runtime. See `docs/decisions/0001-model-selection.md`.
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
