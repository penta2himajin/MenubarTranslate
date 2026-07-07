# Validation — open measurement tasks

Design decisions that depend on **real-hardware measurement not yet performed**.
Each item names what to measure and which decision it can reopen. English-only.

## 1. OS Translation-framework quality as the Critical fallback

Is Apple's on-device Translation framework good enough for ja↔en to serve as the
degraded path under `Critical`? → gates the fallback half of **ADR 0006**.

## 2. ja↔en OS model: download size and call latency

Measure the OS translation model's download size and per-call latency, to size the
ahead-of-time download and confirm the fallback is actually fast enough. → **ADR 0006**.

## 3. 4-bit quantization fidelity for translation

Verify GGUF `Q4_K_M` translation quality on-device (naive MLX 4-bit has been reported
to degrade; the choice here is specifically GGUF `Q4_K_M`). → can reopen **ADR 0001**.

**Measured 2026-07-06** (`mbt-bench`, 5 configs × 16 sentences, transcripts in
`docs/bench/2026-07-06-m2.md`). This **did** reopen ADR 0001 → superseded by
**ADR 0008**:

- TranslateGemma-4B GGUF `Q4_K_M`: JA→EN clean; **EN→JA emitted artifacts in 4/8
  sentences** (stray punctuation, Cyrillic fragments, one fully-Russian output).
  **Root-caused 2026-07-07:** `PromptBuilder.gemma` ended the prompt at
  `<start_of_turn>model` without the trailing newline the official gemma
  template requires. Both engines fed byte-identical token sequences (verified
  by dumping IDs), so the off-template prompt affected both; GGUF `Q4_K_M`
  greedy decoding happened to fall off-distribution on EN→JA while MLX 4-bit
  happened to survive. With the newline restored, all 16 GGUF sentences are
  clean and EN→JA got faster (p50 496 → 350 ms — no wasted artifact tokens);
  MLX output unchanged-clean. **Quantization was not the cause; `Q4_K_M`
  fidelity is adequate.** Report: `docs/bench/2026-07-07-gguf-prompt-fix.md`.
  Consequence: per ADR 0008's own terms the default runtime flips back to GGUF
  (see the 0008 amendment).
- TranslateGemma-4B MLX 4-bit: clean both directions — the reported naive-MLX
  degradation did not reproduce for this model.
- Timings: GGUF cold/warm load 0.44–0.49 s (confirms ADR 0002's ~0.5 s reload);
  MLX load ~2.1–2.3 s. Residency: gemma-mlx ~2.27 GB, hymt-7b-mlx ~4.05 GB,
  hymt-1.8b-mlx ~0.99 GB; GGUF `phys_footprint` deltas are not meaningful (mmap).
- Caveat: measured on a 64 GB machine. Latency/quality transfer; behaviour under
  actual 8 GB memory pressure remains unmeasured.

## 4. MoE expert cache hit-rate (only if the MoE path is revisited)

If a larger-than-RAM MoE model is ever pursued (e.g. Qwen3-30B-A3B) with expert
streaming, measure the expert cache hit-rate to judge viability. → **ADR 0002**.

---

Method note: measurements are on Apple Silicon dev hardware; the primary profile to
report against is the 8 GB unified-memory target, with a 16 GB+ comparison where
relevant.
