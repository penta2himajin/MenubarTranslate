# ADR 0005 — Pressure as an orthogonal state-machine domain

- Status: Accepted
- Date: 2026-07-05
- Related: ADR 0003, ADR 0004

## Context

It is tempting to fold memory-pressure levels into the weight-lifecycle states as
extra linear states. That entangles two independent concerns and produces a
combinatorial, error-prone transition graph.

## Decision

Model the system as **two orthogonal domains** (a `level × state` matrix), not one
linear chain:

- **Domain A — weight lifecycle**: `Unloaded` → `Loading` → `Ready` → `Inferring` →
  `Evicting`.
- **Domain B — memory pressure**: `Normal` / `Warn` / `Critical`.

Domain B modulates Domain A's transitions rather than being interleaved into it:

- `Warn` is **debounced** (per ADR 0004).
- `Critical` acts **immediately** (bypasses the residency floor, forces eviction).

## Consequences

- Each domain stays small and independently testable.
- Pressure handling changes without touching the lifecycle enum, and vice versa —
  this is enforced as an architectural boundary in `AGENTS.md`.

## Alternatives considered

- **Single linear state machine** with pressure baked in: rejected — combinatorial
  blowup and tangled invariants.
