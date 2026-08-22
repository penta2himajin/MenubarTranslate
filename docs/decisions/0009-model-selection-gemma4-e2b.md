# ADR 0009 — Model selection: Gemma 4 E2B, GGUF only, no local fallback

- Status: Accepted
- Date: 2026-07-27
- Supersedes: ADR 0008 (both the model and the runtime choice)
- Related: ADR 0002, ADR 0003, ADR 0004, ADR 0006

## Context

ADR 0008 selected TranslateGemma-4B GGUF `Q4_K_M` by measurement. Gemma 4 shipped
on 2026-03-31 with an E2B variant, which reopened the question.

Before any comparison could be trusted, two defects in the harness had to be
fixed — both of which had silently invalidated parts of ADR 0008's table:

- **Prompt dialect.** `PromptBuilder.hunyuan` hardcoded Hy-MT2-7B's token set.
  Hy-MT2-1.8B uses an incompatible one, and `MLXEngine` sent any unrecognised
  family to a raw, un-templated prompt — which is where Gemma 4 would have
  landed. This is the same failure class ADR 0008's amendment root-caused.
- **Decoder asymmetry.** Every Hy-MT2 configuration in ADR 0008 was measured with
  the model card's sampling (temp 0.7 / top-p 0.6) while every gemma configuration
  was measured greedy. The families were never compared under the same decoder.

With both fixed, the numbers below are the first set in this project that holds
prompt, decoder and runtime constant across candidates. All are GGUF, greedy, on
one machine on one day, at `n_ctx = 1024`; transcripts are byte-identical to the
`n_ctx = 4096` runs. Timings are from a battery-powered machine — read them as
ratios. Full data: `docs/bench/2026-07-27-*.md`.

| Config | Disk | `phys_footprint` | Cold load | p50 | chars/s | License |
|---|---|---|---|---|---|---|
| **gemma4-e2b-gguf** (QAT `q4_0`) | 3.19 GiB | **174.9 MB** | 547 ms | **198.5 ms** | **241.5** | **Apache 2.0** |
| milmmt-4b-gguf (`Q4_K_M`) | 2.67 GiB | 219.8 MB | **366 ms** | 265.3 ms | 174.9 | Gemma |
| gemma-gguf (ADR 0008 default) | 2.32 GiB | 222.2 MB | 337 ms | 330.9 ms | 171.0 | Gemma |
| milmmt-1b-gguf (`Q4_K_M`) | 0.94 GiB | **106.8 MB** | 648 ms | **139.0 ms** | **367.9** | Gemma |

Two measurement notes that changed the conclusion:

**Disk size is the wrong proxy for memory here.** llama.cpp maps weights
file-backed, and `vmmap` shows them resident with `dirty 0 K` — clean pages macOS
can reclaim without swapping. `phys_footprint`, the metric that actually drives
`DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` (ADR 0003), excludes them. What it does
count is the KV cache, and there Gemma 4 E2B's hybrid local/global attention wins
despite being the largest model on disk. See
`docs/bench/2026-07-27-gguf-residency.md`.

**Context size was costing more than the model choice.** The hardcoded
`n_ctx = 4096` served no workload here — prompts run ~100 tokens against a
512-token generation cap. At 1024 every candidate got both faster and lighter
with byte-identical output; the outgoing default alone went from 770 ms to
331 ms p50.

On quality, over the 16-sentence JA↔EN set: Gemma 4 E2B produced no clear error
in either direction and preserved register (casual Japanese stayed casual in
English). TranslateGemma-4B was accurate but drifted formal. MiLMMT-4B dropped
「お世話になっております」entirely and read "finds you well" as "arrives".
MiLMMT-1B carried four EN→JA semantic errors that its 4B sibling does not, so
they are capacity, not prompting.

## Decision

**1. The model is Gemma 4 E2B, GGUF, Google's official QAT `q4_0` build**
(`google/gemma-4-E2B-it-qat-q4_0-gguf`). The multimodal projector ships as a
separate file and is not used.

**2. llama.cpp / GGUF is the only shipping runtime.** MLX is retained as a
development and quantization-experiment path, not a shipping candidate. Gemma 4
E2B could not be loaded through `MLXEngine` — mlx-swift-lm 3.31.4's
`Gemma4Model.sanitize` only remaps keys prefixed `model.`, so the
`language_model.*` layout fails. **See the amendment below: that is a property
of the LLM factory this engine uses, not of MLX.** The decision stands on the
other grounds — mmap-backed load, packaging, and the runtime's own history in
ADR 0008 — but not on impossibility.

**3. `n_ctx` is 4096.** 1024 was enough for the sentence-length bench set;
panel pastes are not. Prefill is chunked at `n_batch = 512` so compute
buffers do not scale with context. `MBT_N_CTX` overrides for benches.

**4. There is no local fallback model.** Degradation under `Critical` pressure
remains exactly what ADR 0006 specifies: lean-load, evict-after-use, and the
capability-gated Apple Translation framework. No second set of weights ships.

## Consequences

- **License obligations drop to the Apache 2.0 minimum** — include the license,
  retain notices. The Gemma Terms path would additionally have required carrying
  its use restrictions into this app's own terms as an enforceable provision,
  shipping the full agreement to users, and a NOTICE file (Gemma Terms §3.1).
  Decision 4 is what preserves this: one Gemma-licensed model anywhere in the
  bundle would have reinstated all of it.
- **ADR 0002's ~0.5 s cold-reload constant survives** — 547 ms measured. The
  residency and eviction policy of ADR 0003/0004 is unchanged; only the model
  behind the constants moves.
- **`phys_footprint` while resident is 174.9 MB**, below the outgoing default's
  222.2 MB, with a further 3.1 GB of reclaimable clean pages. The 8 GB target is
  not made harder by this change.
- **Disk grows 2.49 GB → 3.35 GB.** This is the one axis on which the decision
  loses, and it is accepted: it buys 1.7× lower latency, a better license, and
  no measured quality regression.
- **The `default.metallib` working-directory problem stops blocking packaging.**
  It remains a real defect for the MLX path (`docs/architecture.md`), but that
  path is no longer on the way to a shipped `.app`.
- `PromptBuilder.gemma4` and the `ModelFamily` dispatch in `LlamaEngine` are
  required by this decision; Gemma 4 replaced `<start_of_turn>` with
  `<|turn>role … <turn|>` wholesale.

## Alternatives considered

- **MiLMMT-46-4B.** Faster than Gemma 4 E2B at `n_ctx = 4096` and slower at 1024
  — the apparent advantage was a context artifact. Loses on license (Gemma
  Terms), committed memory, and two clear translation errors.
- **MiLMMT-46-1B as a lean fallback under Critical pressure.** Genuinely
  attractive on resources (106.8 MB committed, 139 ms p50). Rejected on two
  grounds: it reinstates the full Gemma Terms obligation for the whole product,
  and a pressure-driven model swap sits uncomfortably close to the ADR 0004
  prohibition on loading weights in response to pressure. A compliant form exists
  — let pressure choose *which* model the next user-intent load uses, never
  trigger a load — but it is complexity the OS fallback already covers.
- **Keeping TranslateGemma-4B** (ADR 0008). Now dominated: same license class,
  1.7× the latency, register drift, and higher committed memory.
- **Hy-MT2-1.8B.** Re-measured under both decoders after the prompt fix; the
  duplicated clauses, misspellings and mistranslated proper nouns survive both.
  ADR 0008's rejection stands, on stronger evidence. (License is not the reason:
  Hy-MT2 is Apache 2.0 as of 2026-05-26 — see amendment below.)
- **HY-MT1.5-1.8B.** The only other 1–2 B translation model with an official
  GGUF and Japanese support at the time of this ADR. Rejected unmeasured: when
  recorded, the Tencent Hunyuan Community License excluded the EU, UK and South
  Korea from its Territory and forbade use or display of Outputs outside it —
  incompatible with undifferentiated distribution. Hy-MT2 (the successor line)
  later switched to Apache 2.0; see amendment. This ADR did not re-measure
  HY-MT1.5 after that change.
- **NLLB-200-distilled-1.3B.** CC-BY-NC-4.0; non-commercial, and an
  encoder-decoder llama.cpp does not support.

## Open questions

- **Behaviour under real memory pressure on an 8 GB machine is unobserved.** That
  clean file-backed pages *can* be reclaimed follows from their classification,
  measured on a 64 GB machine under no pressure. The re-fault latency penalty
  after reclaim is likewise unmeasured.
- **Quality rests on 16 sentences** read by hand, not a metric. No FLORES or WMT
  text-translation numbers are published for Gemma 4 E2B; its only official
  ja→en figure is CoVoST 21.4 BLEU, which is *speech* translation.
- **Only ja↔en was measured.** Gemma 4 claims 35+ supported languages out of 140+
  pre-trained. Per-language quality is unknown and matters if the language scope
  widens.
- **QAT versus post-training quantization was not isolated.** The QAT build was
  chosen on provenance; Google publishes no E2B-specific QAT-vs-PTQ numbers.
- **MLX was never measured for this model.** See the amendment; the comparison
  that would settle decision 2 on evidence rather than on the ADR 0008
  inheritance has not been run.

## Amendment (2026-07-27): "cannot load on MLX" was wrong

Decision 2 asserted that Gemma 4 E2B cannot load on MLX at all. That is false,
and the error was mine: I concluded it from a single failure path without
checking the alternative.

`mlx-community/gemma-4-e2b-it-4bit` is a `Gemma4ForConditionalGeneration`
checkpoint. `MLXEngine` loads through `LLMModelFactory` (MLXLLM), whose
`Gemma4Model.sanitize` does not handle the `language_model.*` key layout — hence
the `keyNotFound(per_layer_projection_norm)` failure. The **`VLMModelFactory`**
(MLXVLM) path handles it. The sibling `polymorpha` repository runs this exact
checkpoint on this exact mlx-swift-lm version (3.31.4) through
`VLMModelFactory`, with two small patches against `Libraries/MLXVLM/` for
KV-shared layers and the E2B masked embedder.

So the correct statement is *"not through the factory `MLXEngine` uses"*, not
*"not on MLX"*.

This does not by itself reverse decision 2, which also rests on mmap-backed
loading, packaging, and ADR 0008's history. But it removes the argument that
made the decision look forced, and it leaves a real question open: MLX on this
model was never measured. Gemma 4 E2B additionally has an MTP assistant that
`polymorpha` measures at 155.6 tok/s steady against 111.2 baseline — a path
GGUF does not have. Whether that survives contact with short translation
inputs, where prefill and load dominate, is unknown; `polymorpha`'s numbers are
generation throughput and are not comparable to this ADR's per-sentence
latencies without re-measuring on the same 16-sentence set.

Weighing against it, unchanged: MLX has no mmap equivalent (measured 4.2x worse
cold load on MiLMMT-1B, 1546 vs 366 ms), which ADR 0003/0004's evict-and-reload
design is built around; the MTP drafter is an additional resident model against
an 8 GB target; and the MLX path needs an Xcode build plus two carried upstream
patches.

## Amendment (2026-08-14) — `n_ctx` 1024 truncated panel pastes

Decision 3 originally set `n_ctx = 1024` because the 16-sentence bench set
used ~100-token prompts and a 512-token generation cap. Real menu-bar pastes
filled the KV cache mid-decode (`decode: failed to find a memory slot for
batch of size 1`) and returned a truncated translation. The default is 4096;
generation now runs until EOS or the remaining context, not a fixed 512.
`MBT_N_CTX=1024` still reproduces the bench configuration.

## Amendment (2026-08-22) — Hy-MT2 is Apache 2.0

Hy-MT2 was originally published under the Tencent HY Community License
(territory limits including EU exclusion). On 2026-05-26 the upstream repo
renewed the licence to Apache License 2.0
([Tencent-Hunyuan/Hy-MT2@c30b36c](https://github.com/Tencent-Hunyuan/Hy-MT2/commit/c30b36c59b19252dae7f3afca34d8478dbe67de9)).

Verified 2026-08-22 against current upstream text:

- GitHub `LICENSE.txt`: *"Hy-MT2 is licensed under the Apache License, Version 2.0."*
- Hugging Face model cards tag `license: apache-2.0` (e.g. `tencent/Hy-MT2-1.8B`)
- Matching `LICENSE.txt` on `tencent/Hy-MT2-1.8B`, `tencent/Hy-MT2-7B`, and the
  GGUF repos (`…-1.8B-GGUF`, `…-7B-GGUF`)

This does **not** reverse the Hy-MT2-1.8B rejection in this ADR, which rests on
measured quality. It does remove the Community-License / territory argument as
a reason not to consider Hy-MT2 weights for experiments or a future revisit.
Gemma 4 E2B remains the shipping default.
