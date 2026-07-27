# GGUF residency — what an mmap-backed model actually costs

Date: 2026-07-27 | Machine: Apple Silicon, 64 GB, macOS 26.5.2 | llama.cpp b9878
Context size: 4096 (`LlamaEngine` default). All three configs are GGUF.

## Why this measurement exists

ADR 0008 recorded GGUF residency as `(mmap)*` with the note that
`phys_footprint` deltas "do not reflect the true working set", and left it
there. Since the project's primary constraint is **8 GB unified memory** and the
model-selection candidates differ by 3.3× on disk, "not comparable" was not good
enough to choose a default on.

`mbt-bench` samples `phys_footprint` from inside the process. This run instead
observes each process from outside — peak RSS via `ps`, and page classification
via `vmmap --summary` taken ~3 s into the run.

## Results

| Config | On disk | Peak RSS | `phys_footprint` | mapped file (resident / dirty) |
|---|---|---|---|---|
| gemma4-e2b-gguf | 3.19 GiB | 3396 MB | **229.9 MB** | 3.1 GB / **0 K** |
| milmmt-4b-gguf | 2.67 GiB | 3377 MB | **628.3 MB** | 2.7 GB / **0 K** |
| gemma-gguf (TranslateGemma-4B) | 2.32 GiB | 3019 MB | **628.3 MB** | 2.3 GB / **0 K** |
| milmmt-1b-gguf | 0.94 GiB | 1156 MB | **187.8 MB** | 972.5 MB / **0 K** |

## What the numbers mean

**The weights are clean, file-backed pages — `dirty 0 K` across the board.**
macOS can reclaim them under memory pressure without swapping; they are re-read
from disk on the next fault. This is the mechanism behind ADR 0008's claim that
mmap-backed weights "degrade more gracefully under memory pressure", stated
there without a measurement. It now has one.

**`phys_footprint` excludes those pages by design.** It is the metric macOS
charges against a process and uses to drive memory-pressure notifications — the
same signal `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` (ADR 0003) reacts to. The
bench's internal number was not broken; it was measuring committed memory, which
for an mmap-backed model is *not* the weights.

**On that metric the disk-size ranking inverts.** Both Gemma 3 4B-class models
— TranslateGemma-4B and MiLMMT-46-4B — charge 628.3 MB, to the tenth of a
megabyte; Gemma 4 E2B charges 230 MB, **2.7× less while being the largest of the
three on disk**. The identical figure for the two Gemma 3 models is the tell:
this is KV cache, not weights. Gemma 3 runs full attention across its layers at
4096 context, whereas Gemma 4 E2B's hybrid local-sliding-window + global
attention collapses it. Model size on disk turns out to be the wrong proxy for
the memory that actually matters here.

## Context size dominates both memory and speed

The 4096 default was never justified by the workload — prompts here run ~100
tokens and generation is capped at 512. Re-running every config at
`MBT_N_CTX=1024`, with **byte-identical transcripts in all four cases**:

| Config | footprint 4096 → 1024 | cold 4096 → 1024 | p50 4096 → 1024 | p95 4096 → 1024 | chars/s 4096 → 1024 |
|---|---|---|---|---|---|
| gemma4-e2b-gguf | 229.9 → **174.9 MB** | 725 → 547.3 ms | 317 → **198.5 ms** | 999 → 320.8 ms | 134 → **241.5** |
| milmmt-4b-gguf | 628.3 → **219.8 MB** | 472 → 365.8 ms | 296 → **265.3 ms** | 743 → 487.0 ms | 136 → **174.9** |
| gemma-gguf (shipping default) | 628.3 → **222.2 MB** | 448 → 337.3 ms | 770 → **330.9 ms** | 1291 → 527.2 ms | 76 → **171.0** |
| milmmt-1b-gguf | 187.8 → **106.8 MB** | 366 → 648.1 ms* | 248 → **139.0 ms** | 438 → 235.0 ms | 215 → **367.9** |

\* milmmt-1b's cold load went up rather than down; its warm reload in the same
run was 280.6 ms, so this is a cold page cache, not a context effect.

The `n_ctx = 1024` transcripts are not stored separately: they were diffed
against the 4096 runs above and are byte-identical in all four cases, which is
the finding. The numbers that do differ are in this table.

Two consequences worth separating from the model-selection question:

**The shipping configuration was leaving 2.3× latency on the table.** Nothing
about the model changed — TranslateGemma-4B goes from 770 ms to 331 ms p50 purely
by sizing the context to the workload.

**The KV-cache argument for Gemma 4 E2B is largely a 4096 artifact.** At 4096 it
charged 398 MB less than the Gemma 3 4B models; at 1024 the gap is 45 MB. What
survives the context change is the *speed* ranking, and it inverts: at 4096
MiLMMT-4B looked faster than Gemma 4 E2B (296 vs 317 ms), at 1024 Gemma 4 E2B is
clearly ahead (198.5 vs 265.3 ms). Gemma 4's hybrid attention benefits more from
a smaller window than full attention does.

## Limits of this measurement

- Taken on a 64 GB machine with **no memory pressure present**. That clean pages
  *can* be reclaimed follows from their classification; how an 8 GB machine
  actually behaves under real pressure was not observed.
- Reclaim is not free — re-faulting weights costs page-ins on the next
  inference. That latency penalty is unmeasured.
- Peak RSS still competes for physical RAM against other applications even
  though it is reclaimable; 3.4 GB resident is not "free" on an 8 GB machine.
- Both context sizes were measured; nothing here has been checked at a context
  large enough to matter for long-document translation, which the app does not
  currently do.
- Single sample per config, `vmmap` taken ~3 s in rather than at peak.

## Reproducing

```bash
swift build -c release
# peak RSS
.build/release/mbt-bench --only <config> --out /dev/null &
BP=$!; while kill -0 $BP 2>/dev/null; do ps -o rss= -p $BP; sleep 0.2; done

# page classification
.build/release/mbt-bench --only <config> --out /dev/null &
BP=$!; sleep 3; vmmap --summary $BP | grep -E "^Physical footprint:|mapped file"
```
