# ADR 0004 — Thrash avoidance: asymmetric evict/load + hysteresis

- Status: Accepted
- Date: 2026-07-05
- Related: ADR 0003, ADR 0005

## Context

A naive policy that both evicts *and* loads in response to memory pressure will
oscillate: pressure evicts the weights, the app reloads them, which raises pressure,
which evicts again. This evict↔load thrash is the central risk of managed residency.

## Decision

The core rule is an **asymmetry of triggers**:

- **Eviction** reacts to `pressure` ∨ `idle timeout`.
- **Loading** reacts to **user intent only** — never to a pressure event.

Because nothing automatically reloads under pressure, the oscillation loop cannot
form. This is reinforced by **double hysteresis**:

1. A **residency floor**: a minimum time weights stay resident after a load, so a
   burst of `warn` right after loading cannot immediately evict.
2. **`warn` debounce**: transient `warn` blips are debounced before acting.

Exceptions:

- **`critical`** ignores the residency floor and evicts **immediately**.
- **Speculative prewarm** (if used) carries a short **TTL** and auto-unloads, so it
  can never pin memory.

## Consequences

- Evict↔load oscillation is removed by construction, not by tuning.
- Loading is strictly user-driven, keeping latency cost visible and intentional.

## Alternatives considered

- **Symmetric pressure-driven load+evict**: rejected — this is exactly the thrash
  source.
- **Hysteresis alone (symmetric triggers)**: reduces but does not eliminate
  oscillation; the trigger asymmetry is what makes it impossible.
