# ADR 0010 — Distribution: unsigned release via Homebrew, model fetched by script

- Status: Accepted
- Date: 2026-07-27
- Related: ADR 0006, ADR 0009

## Context

ADR 0009 settled which weights the app runs. It did not say how those weights
reach a user, and today nothing does: there is no packaging script, no
`Info.plist`, no bundle identifier, and `swift build` emits a bare executable
rather than a `.app`. The project can be run, not delivered.

Two facts shape the decision.

**The model is 3.35 GB and is not in the repository.** `models/*` is gitignored,
correctly — multi-gigabyte GGUF blobs do not belong in git.

**The default model path is relative** — `models/weights/gemma-4-E2B_q4_0-it.gguf`
— so it only resolves when the process is launched from the repo root. This is
the same defect class as the `default.metallib` working-directory problem
recorded in `docs/architecture.md`, except this one sits on the shipping path: a
packaged `.app` runs with an arbitrary working directory and would fail at
launch.

A survey of comparable projects found that **every consumer GUI in this space
ships an in-app downloader** — LM Studio, GPT4All, Jan, MacWhisper. Keeping the
fetch outside the binary is a developer-tooling pattern: whisper.cpp's
`models/download-ggml-model.sh` is the closest precedent, with Ollama's
daemon/CLI split and Hugging Face's own `hf` CLI as the other instances. Notably
LM Studio, despite its in-app downloader, still converged on a companion CLI
(`lms get`). The choice below is the minority one, and matches the audience.

The local-only invariant (prohibition #1) reads: *nothing on the translation
path may make a network call*. `NetworkGuard` enforces exactly that scope — it
is injected into `TranslationService` and guards inference, not the process.

## Decision

**1. The model is fetched by `scripts/fetch-model.sh`, outside the app.** Not
bundled — a 3.4 GB re-download for every code change is the worse trade — and
not downloaded by the app itself, for the reason in decision 2.

The source is pinned to the exact bytes ADR 0009 measured:

```
repo      google/gemma-4-E2B-it-qat-q4_0-gguf
revision  675cff42a74c774d6cb76f76d8eacb49b48c9b93
file      gemma-4-E2B_q4_0-it.gguf
size      3,349,516,256 bytes
sha256    fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634
```

Pinning the revision rather than tracking `main` means an upstream re-upload
cannot silently change what users run. The digest was verified against the local
artifact every measurement in ADR 0009 was taken on.

**2. The shipped binary contains no network code at all.** This is the point of
keeping acquisition outside the app. "Local-only" stops being a promise about
when the app chooses to use the network and becomes a structural property that
can be checked from outside — there is no HTTP client linked into the product.
`NetworkGuard` is unchanged and stays `.deny`-only; do not add a permissive case
for a downloader that no longer exists in the binary.

**3. Weights live in `~/Library/Application Support/MenubarTranslate/models/`.**
Resolution order becomes: `MBT_LLAMA_GGUF` (development override) → Application
Support → absent. The relative default is removed. One location serves both the
`.app` and the `mbt` CLI.

Application Support rather than `Caches/`: the system may purge caches, and a
purged model is a silently broken app. The file is marked
`isExcludedFromBackupKey`, per Apple's guidance that anything re-downloadable
should not be backed up — without it every Time Machine and iCloud backup grows
by 3.35 GB. The key is advisory, and how Time Machine honours it on macOS is not
clearly documented.

**4. Consent, resume and verification are the script's, and are nearly free
there.** In-app they would have meant a SwiftUI progress sheet, `URLSession`
range handling and interrupt/restart state. As shell, they are tools already
present on every Mac:

- *Consent*: a prompt before fetching 3.35 GB. Doing that unprompted on a
  metered connection is not acceptable behaviour.
- *Resume*: attempted with `curl -L -C -` against the canonical `resolve` URL.
  Interruption is the normal case at this size — a Hugging Face download stalled
  at 79 MB for thirty minutes during the ADR 0009 work and had to be killed and
  restarted. **How reliable curl resume is against Hugging Face is unverified.**
  HF redirects to signed CDN URLs that expire within minutes; re-issuing against
  the canonical URL should obtain a fresh redirect each time, but that is
  mechanistic inference, and HF's own documentation simply steers everyone to
  `hf download`. Users have reported curl timing out on very large files.
- *Verification*: `shasum -a 256` against the pinned digest — and this is what
  actually carries the design. Resume is an optimisation that may or may not
  work; the digest is what guarantees a partial or corrupted transfer is caught
  rather than used. A truncated GGUF does not crash; it mmaps and produces
  degraded translations. On mismatch the script says so and asks to be re-run.

`hf download` has real LFS-aware resume, but requires a Python environment. That
is a heavier prerequisite than the whole rest of this flow, so `curl` — present
on every Mac — is used and the digest covers its failure modes.

Choosing the script does not relocate this machinery so much as delete most of
it.

**5. The app fails loudly and helpfully when the model is absent**, naming the
script and the expected path. This is the cost of moving acquisition out: the
user can now arrive at a `.app` with no weights, and the one thing that must not
happen is a silent failure. It is not optional.

**6. Distribution is a Homebrew cask, plus an unsigned archive on GitHub
Releases. The cask installs the `.app` only.** Model acquisition is surfaced
through `caveats`, which is Homebrew's sanctioned mechanism for installation-
related follow-up steps, rather than run from `postflight`.

Fetching the model from the cask was considered and rejected on Homebrew's own
mechanics: every cask `url` is cached under `brew --cache`, so the 3.35 GB would
exist twice on disk until `brew cleanup`; `brew upgrade` re-downloads the cask
artifact on every version bump; casks have no `resource` stanza; and `postflight`
is being deprecated in favour of declarative `postflight_steps`. No precedent
cask fetching multi-gigabyte data was found, and the documentation does not model
the case.

Both channels are unsigned: Gatekeeper will refuse a double-click and the cask
needs `--no-quarantine`. The README documents both paths in each language.
Signing is deferred, not rejected — see Open questions.

**7. The bundle is produced by `scripts/package-app.sh`**, alongside the existing
`scripts/build-llama-xcframework.sh`. It emits a `.app` with an `Info.plist`
carrying `LSUIElement` and a bundle identifier
(`io.github.penta2himajin.MenubarTranslate`, chosen because it is a namespace the
author demonstrably controls).

## Consequences

- **The relative-path defect is fixed as a side effect.** Path resolution stops
  depending on the working directory, which is what made the current default
  unusable outside the repo root.
- **The local-only claim becomes auditable.** No HTTP client is linked into the
  shipped product, so the invariant holds for the whole binary rather than only
  the translation path `NetworkGuard` covers.
- **ADR 0006's Translation-framework fallback reverts to a memory-pressure path
  only.** An earlier draft of this ADR justified it as also covering the
  first-run download window; with acquisition moved before launch there is no
  such window, and the fallback needs no second justification.
- **Apache 2.0 obligations become concrete.** ADR 0009 claimed the licence cost
  drops to "include the licence, retain notices"; this is where that is paid. The
  bundle ships Gemma's Apache 2.0 licence text and a NOTICE, and llama.cpp's MIT
  licence.
- **`LSUIElement` in the plist supersedes the programmatic
  `NSApp.setActivationPolicy(.accessory)`** in `AppDelegate`. The call stays, so
  `swift run` keeps behaving the same during development.
- **Unsigned means friction.** Users must clear Gatekeeper manually, and some
  will not. Accepted while the audience is developers; the first thing to revisit
  when it is not.
- **A model change becomes an app update plus a re-fetch**, because the revision
  and digest live in the script. `brew upgrade` re-runs `postflight`; the archive
  path requires running the script again. Intentional: it keeps the shipped model
  identical to the measured one.
- **A new tap repository is required** (`penta2himajin/homebrew-tap`) before the
  cask can be installed by name.
- **`brew install --cask` no longer yields a working app on its own.** The
  caveat is the only thing standing between a user and an app that launches
  without weights, which is what makes decision 5's loud failure load-bearing
  rather than a nicety.

## Alternatives considered

- **Download inside the app on first run.** Better product behaviour — one
  double-click and it works. Rejected on auditability: it puts an HTTP client in
  a binary whose selling point is that it never uses the network, reducing a
  checkable property to a promise. It would also have required rebuilding
  consent, resume and verification that `curl` and `shasum` already provide.
- **A Swift installer binary** rather than a shell script. Rejected: it adds an
  opaque executable the user must trust, where a script can simply be read. Worse
  on the same axis that motivated moving acquisition out in the first place.
- **Bundle the weights in the `.app`.** Strongest possible reading of the
  local-only invariant — zero network, ever, including at install. Rejected on
  update economics: every code change would ship 3.4 GB, and users would
  re-download the model to get a bug fix.
- **Leave acquisition entirely to the user** (status quo: place the file
  yourself, or set `MBT_LLAMA_GGUF`). Zero implementation. Rejected because it is
  not a product; it keeps the app permanently a developer tool. The env override
  is retained for development.
- **Widen `NetworkGuard.Policy`** with an `.allowModelFetch` case, for symmetry.
  Rejected: no downloader exists in the binary, so the case would be unreachable
  while making the invariant look negotiable.
- **Track the Hugging Face `main` revision** instead of pinning. Rejected:
  upstream could replace the file and every user would silently be running
  something no measurement in this repository covers.
- **Sign and notarize now.** Requires a paid Apple Developer account and
  certificate handling in CI, for an audience that can clear Gatekeeper.
  Deferred.

## Open questions

- **Signing and notarization**, and with it the Mac App Store route (which would
  additionally require sandboxing, and a sandboxed app cannot read an arbitrary
  Application Support path without entitlements).
- **What happens when the pinned model 404s.** Hugging Face repositories can be
  renamed or gated after the fact; there is no mirror and no fallback source.
- **Whether `curl -C -` resume actually works against Hugging Face.** The digest
  makes a failed resume safe rather than silent, but if resume turns out not to
  work at all, a user on a poor connection may never complete a 3.35 GB transfer.
  Worth measuring by interrupting a real download; `aria2c -c` and `hf download`
  are the fallbacks, both at the cost of a dependency.
- **Whether `isExcludedFromBackupKey` is honoured by Time Machine.** Apple
  documents it as advisory and writes the guidance for iOS/iCloud; macOS
  behaviour is not clearly specified. If it is ignored, users' backups grow by
  3.35 GB and the alternative is a documented Time Machine exclusion.
