# ADR 0001 — Model selection: TranslateGemma-4B (GGUF Q4_K_M)

- Status: Accepted
- Date: 2026-07-05

## Context

MenubarTranslate runs translation fully on-device, JA↔EN primary, with 8 GB unified
memory as the primary target. The model must fit alongside the OS and a normal
desktop working set, load fast enough for interactive use, and translate well enough
that an on-device experience is worth shipping.

Candidates considered:

- **TranslateGemma-4B** — Gemma-3-based, Dense, multimodal.
- **plamo-2-translate** — PLaMo2 (Samba / Mamba hybrid), Japanese-specialised.
- **MoE options** (e.g. Qwen3-30B-A3B class) — large, sparsely-activated.

## Decision

Ship **TranslateGemma-4B in GGUF `Q4_K_M`**: roughly **2.5 GB on disk** and
**~3–3.5 GB resident** at runtime, on a llama.cpp / Metal backend.

## Consequences

- Fits the 8 GB target with headroom for the OS and other apps, provided residency
  is actively managed (see ADR 0003).
- The model is **Dense** (no MoE, no exploitable ReLU sparsity). This directly rules
  out per-token weight streaming (ADR 0002).
- `Q4_K_M` fidelity for translation is assumed adequate but **not yet verified** on
  real hardware — see `docs/validation.md`.

## Alternatives considered

- **plamo-2-translate**: attractive as a JA-specialised hybrid, but deprioritised in
  favour of TranslateGemma's fit and the simpler Dense/GGUF/Metal path.
- **MoE**: deprioritised for the primary product. Retained only as a possible future
  path if a model larger than RAM is pursued, where expert streaming becomes relevant
  (see ADR 0002).
