# ADR 0006 — Critical-pressure degradation and OS Translation fallback

- Status: Accepted
- Date: 2026-07-05
- Related: ADR 0003, ADR 0004, ADR 0005

## Context

Under `Critical` memory pressure the app may still receive a user translation
request. Loading the full ~3–3.5 GB model then is risky. We want to still answer,
degrade gracefully, and never assume a fallback exists.

## Decision

On **`Critical` + user intent**:

1. **Lean-load** the model — omit the vision tower, use a minimal context — and
   **evict immediately after use** (per ADR 0004's asymmetry: this is intent-driven).
2. Additionally, **capability-gated** fallback to Apple's on-device **Translation
   framework** (the dedicated translation framework, *not* the AFM 3 Core model).

The capability gate is a **three-layer availability check**:

- the API is present, **and**
- ja↔en is a supported pair, **and**
- the OS translation model has already been downloaded.

The OS model download is performed ahead of time, while pressure is `Normal`, so the
fallback is ready before it is needed.

## Consequences

- The app degrades instead of failing or OOM-ing under `Critical`.
- The fallback is never assumed: if any gate layer is false, it is simply unavailable
  and the app falls back to lean-load only.
- Fallback **quality** (is the Translation framework good enough for ja↔en?) and the
  OS model's **download size / call latency** are **not yet measured** — see
  `docs/validation.md`. This ADR may reopen if the fallback proves inadequate.

## Alternatives considered

- **AFM 3 Core model** instead of the Translation framework: rejected — the dedicated
  translation framework is the right tool for the pair-translation task.
- **No fallback (fail under Critical)**: rejected — poor UX at the exact moment the
  app is most constrained.
