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

## App layer

The core stays SwiftUI-free. `AppRuntime` is the public facade (translate, tick,
snapshot/onChange), `AppViewModel` (@Observable, Observation only) sits on top for
binding, and the `MenubarTranslateApp` target (`app/`, macOS 15) owns everything
OS-facing: the `MenuBarExtra` shell, a 1 s tick loop driving idle-timeout, and the
Translation-framework wiring — `LanguageAvailability` probes feed the ADR 0006
capability gate, and live `TranslationSession`s are handed to the core through
`OSTranslationEngine`'s closure seams. Default runtime is llama.cpp/GGUF (ADR 0008);
MLX is the alternate.

## Known upstream issues

**llama.cpp b9878 aborts at process teardown.** A `ggml-metal` static destructor
trips `GGML_ASSERT([rsets->data count] == 0)` (`ggml-metal-device.m:622`) after a
successful run, turning a clean exit into signal 6 / exit code 134. It fires after
all work has completed, so results are unaffected — but it corrupts the exit status,
which matters for scripting and CI.

Both entry points therefore end with `_exit(0)` rather than `exit(0)`, skipping
`atexit` handlers and static destructors (`mbt/main.swift`, and the Quit / restart
buttons in `app/MenubarTranslateApp.swift`). This is safe because all output goes
through unbuffered `FileHandle` writes, so there is nothing to flush.

`swift test` has no such escape hatch: the assert fires in the test harness after
the suite reports, so a fully green run can still surface as `exited with unexpected
signal code 6`. **Read the `Test run with N tests ... passed` line, not the process
exit status.** Re-check this when the pin in `scripts/build-llama-xcframework.sh`
moves; the workarounds can go once upstream fixes the destructor.

## Open questions

Several choices rest on measurements not yet done on real hardware. See
`docs/validation.md`; results there may reopen ADR 0001 or 0006.

The implementation language and toolchain are **settled**: native Swift + SwiftUI via
SwiftPM (ADR 0007).
