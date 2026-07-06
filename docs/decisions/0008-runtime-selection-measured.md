# ADR 0008 — Runtime selection: TranslateGemma-4B on MLX 4-bit (measured)

- Status: Accepted
- Date: 2026-07-06
- Supersedes: ADR 0001

## Context

ADR 0001 selected TranslateGemma-4B in GGUF `Q4_K_M` on llama.cpp / Metal, with
`Q4_K_M` translation fidelity explicitly flagged as unverified. Milestone 2 built
real engines for both runtimes (llama.cpp b9878, mlx-swift-lm 3.31.4) and measured
five configurations with `mbt-bench` (16 fixed sentences, both directions, on a
64 GB Apple Silicon dev machine — full report and transcripts:
`docs/bench/2026-07-06-m2.md`):

| Config | Cold load | Warm reload | Resident Δ | p50 latency | Throughput |
|---|---|---|---|---|---|
| gemma-mlx | 2.25 s | 2.09 s | 2.27 GB | 891 ms | 60 chars/s |
| hymt-1.8b-mlx | 0.64 s | 0.61 s | 0.99 GB | 405 ms | 125 chars/s |
| hymt-7b-mlx | 0.96 s | 0.96 s | 4.05 GB | 721 ms | 70 chars/s |
| gemma-gguf | 0.44 s | 0.45 s | (mmap)* | 496 ms | 121 chars/s |
| hymt-7b-gguf | 0.49 s | 0.47 s | (mmap)* | 828 ms | 54 chars/s |

\* llama.cpp maps weights file-backed; `phys_footprint` deltas (~0.55 GB) do not
reflect the true working set, so the GGUF residency numbers are not comparable.

Quality findings from the transcripts:

- **gemma-gguf (`Q4_K_M`)**: JA→EN clean, but **EN→JA produced artifacts in 4 of 8
  sentences** — stray leading punctuation, Cyrillic fragments, and one output
  emitted entirely in Russian. Root cause (quantization fidelity vs. engine
  prompt/sampling handling) is not yet isolated — tracked in `docs/validation.md`.
- **gemma-mlx (4-bit)**: clean in both directions. The reported "naive MLX 4-bit
  degrades" concern did not reproduce for TranslateGemma-4B.
- **hymt-7b-mlx**: quality peer of gemma-mlx or slightly better, but 4.05 GB
  resident does not fit the 8 GB primary target alongside a desktop working set.
- **hymt-7b-gguf**: mostly good with occasional lexical errors (のぞみ → ノミ,
  内閣 → 内); slowest p95 (2.2 s).
- **hymt-1.8b-mlx**: fastest and smallest, but EN→JA shows duplicated clauses,
  misspellings and hallucinated content. Below the shipping bar.

## Decision

The default engine is **MLXEngine running TranslateGemma-4B MLX 4-bit**
(~2.3 GB resident). The model choice of ADR 0001 stands; the runtime choice is
reversed by measurement.

The llama.cpp GGUF path stays available behind `--engine llama` and remains the
preferred runtime **if** the EN→JA artifacts are root-caused and fixed: it loads
~4× faster, decodes ~2× faster, and its mmap-backed weights degrade more
gracefully under memory pressure.

Hy-MT2-7B (MLX) is recorded as a quality option for 16 GB+ configurations only.
Hy-MT2-1.8B is rejected on output quality despite the best speed and footprint.

## Consequences

- ADR 0002's "cold reload ≈ 0.5 s" figure is **confirmed for GGUF only**
  (0.44–0.49 s measured). MLX warm reload measured ~2.1 s, so on the 8 GB preset
  every idle-evict → reload costs ~2 s until the GGUF path is fixed. The
  residency/eviction policy (ADR 0003/0004) is unchanged; only the reload-cost
  constant differs.
- The ~2.3 GB resident cost fits the 8 GB envelope as ADR 0001 projected.
- Both engines remain built and tested; a runtime fix on the GGUF path can flip
  the default back without re-opening the model choice.

## Alternatives considered

- **Keep gemma-gguf as default** (ADR 0001): rejected while EN→JA emits garbage
  tokens; a translation app cannot ship that path as the default.
- **hymt-7b-mlx as default**: best transcripts, but 4.05 GB resident breaks the
  8 GB primary target.
- **hymt-1.8b-mlx as default**: rejected on quality (hallucinations, duplicated
  clauses in EN→JA).
- **hymt-7b-gguf as default**: lexical errors plus the same unresolved GGUF
  pipeline questions, without gemma's quality headroom.
