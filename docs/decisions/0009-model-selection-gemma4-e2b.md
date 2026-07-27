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
E2B cannot load on MLX at all — mlx-swift-lm 3.31.4's `Gemma4Model.sanitize`
only remaps keys prefixed `model.`, so the `language_model.*` layout fails —
which settles the question for this model regardless of the general argument.

**3. `n_ctx` is 1024.** This is a statement about the longest input the app
accepts, not a tuning constant.

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
  ADR 0008's rejection stands, on stronger evidence.
- **HY-MT1.5-1.8B.** The only other 1–2 B translation model with an official
  GGUF and Japanese support. Rejected unmeasured: the Tencent Hunyuan Community
  License excludes the EU, UK and South Korea from its Territory and forbids use
  or display of Outputs outside it — incompatible with undifferentiated
  distribution.
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
