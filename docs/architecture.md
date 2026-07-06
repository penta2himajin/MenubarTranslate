# Architecture

Engineering overview for MenubarTranslate. English-only per `docs/i18n-policy.md`.
This document is the narrative; the binding decisions live in `docs/decisions/`.

## Goal and constraints

A local-only macOS menu bar app translating JA↔EN on Apple Silicon. No translation
traffic leaves the device. Primary target: **8 GB unified memory**; 16 GB+ supported
with more permissive residency.

## Inference core

TranslateGemma-4B, GGUF `Q4_K_M` (~2.5 GB disk, ~3–3.5 GB resident), on a
llama.cpp / Metal runtime (ADR 0001). The model is Dense, which shapes the whole
memory strategy.

## Memory strategy

Because the model is Dense, per-token weight streaming is bandwidth-bound and is not
used (ADR 0002). Instead the process stays alive and only **weights** are evicted and
reloaded — *weight-level residency* — amortising Metal/runtime init. A cold reload of
~2.5 GB is ~0.5 s.

Residency is managed by live signals, not by installed-RAM buckets (ADR 0003): RAM
tier only sets an initial preset; actual eviction is driven by **idle timeout ∨
memory pressure** (`DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`). 8 GB evicts by default;
16 GB persistent residency is opt-in.

## Why it does not thrash

The key property (ADR 0004): **eviction reacts to pressure/timeout, loading reacts to
user intent only.** Nothing auto-reloads under pressure, so the evict↔load loop cannot
form. Double hysteresis (a residency floor + `warn` debounce) absorbs transients;
`critical` overrides the floor and evicts immediately; speculative prewarm carries a
short TTL and auto-unloads.

## State model

Two orthogonal domains (ADR 0005), a `level × state` matrix rather than one linear
chain:

- **Weight lifecycle**: `Unloaded → Loading → Ready → Inferring → Evicting`.
- **Pressure**: `Normal / Warn / Critical` — `Warn` debounced, `Critical` immediate.

## Degradation path

Under `Critical` + user intent (ADR 0006): lean-load (no vision tower, minimal
context) + evict-after-use, plus a **capability-gated** fallback to Apple's on-device
Translation framework. The gate requires: API present ∧ ja↔en supported ∧ OS model
already downloaded (download done ahead of time while `Normal`).

## Open questions

Several choices rest on measurements not yet done on real hardware. See
`docs/validation.md`; results there may reopen ADR 0001 or 0006.

The implementation language and toolchain are **settled**: native Swift + SwiftUI via
SwiftPM (ADR 0007).
