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

## Limits of this measurement

- Taken on a 64 GB machine with **no memory pressure present**. That clean pages
  *can* be reclaimed follows from their classification; how an 8 GB machine
  actually behaves under real pressure was not observed.
- Reclaim is not free — re-faulting weights costs page-ins on the next
  inference. That latency penalty is unmeasured.
- Peak RSS still competes for physical RAM against other applications even
  though it is reclaimable; 3.4 GB resident is not "free" on an 8 GB machine.
- KV cache scales with context. The comparison holds at `n_ctx = 4096` only.
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
