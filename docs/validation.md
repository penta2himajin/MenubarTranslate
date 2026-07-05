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

## 4. MoE expert cache hit-rate (only if the MoE path is revisited)

If a larger-than-RAM MoE model is ever pursued (e.g. Qwen3-30B-A3B) with expert
streaming, measure the expert cache hit-rate to judge viability. → **ADR 0002**.

---

Method note: measurements are on Apple Silicon dev hardware; the primary profile to
report against is the 8 GB unified-memory target, with a 16 GB+ comparison where
relevant.
