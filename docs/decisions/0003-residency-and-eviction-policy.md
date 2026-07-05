# ADR 0003 — Residency and eviction policy

- Status: Accepted
- Date: 2026-07-05
- Related: ADR 0002, ADR 0004, ADR 0005

## Context

Weights are resident for speed but cost ~3–3.5 GB. On 8 GB machines that must be
reclaimable; on 16 GB+ machines it can often stay put. RAM size alone is a crude
signal — the real question is whether memory is actually under pressure right now.

## Decision

- **RAM tier is an initial preset only**, not the eviction trigger.
- Actual eviction is driven by **idle timeout ∨ memory pressure**, where pressure is
  read from `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` (`normal` / `warn` / `critical`).
- **8 GB**: eviction is the default (short-ish idle timeout, evict on pressure).
- **16 GB+**: persistent residency is available as an **opt-in** setting. Unbounded
  (`∞`) residency is discouraged; prefer a long but finite timeout.

## Consequences

- Behaviour adapts to live conditions rather than a static RAM bucket.
- Combined with ADR 0004, load and evict triggers are deliberately asymmetric to
  avoid oscillation.
- The `critical` level bypasses the residency floor and evicts immediately (ADR 0004).

## Alternatives considered

- **Pure RAM-tier policy** (evict/keep purely by installed RAM): rejected — ignores
  actual pressure and either wastes memory or evicts needlessly.
- **Always resident**: rejected for 8 GB; discouraged even at 16 GB.
