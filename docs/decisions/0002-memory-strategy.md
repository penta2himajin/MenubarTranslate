# ADR 0002 — Memory strategy: no per-token weight streaming; weight-level residency

- Status: Accepted
- Date: 2026-07-05
- Related: ADR 0001, ADR 0003

## Context

To keep resident memory low on 8 GB machines, one tempting idea is to stream weights
from NAND per token ("LLM in a flash" style), keeping only a working slice in RAM.

The chosen model (ADR 0001) is **Dense**. The flash-streaming speedups in the
literature depend on **MoE routing or activation sparsity** (e.g. ReLU) to avoid
touching most weights per token. A Dense model touches (nearly) all weights every
token, so streaming would be **bandwidth-bound** and defeat interactivity.

## Decision

1. **Do not** stream weights per token for the Dense model.
2. Instead use **weight-level residency**: keep the process (and its Metal / runtime
   initialisation) alive, and evict/reload only the model weights. This amortises
   runtime init across sessions. A cold reload of ~2.5 GB is ~0.5 s.

## Consequences

- Simpler, predictable performance: either weights are resident (fast) or they are
  not (one ~0.5 s reload), with no per-token I/O tax.
- Residency must be actively managed to hold the 8 GB target — the policy lives in
  ADR 0003, and thrash avoidance in ADR 0004.

## Alternatives considered

- **Per-token NAND streaming**: rejected for Dense weights (bandwidth-bound).
- **MoE expert streaming**: only reconsidered if a model larger than RAM is pursued
  (e.g. Qwen3-30B-A3B), where per-token active experts are a small fraction of weights.
  Expert cache hit-rate would then need measurement (see `docs/validation.md`).
