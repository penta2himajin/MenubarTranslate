# MenubarTranslate

## Overview

MenubarTranslate is a **local-only** macOS menu bar translation app. The primary
direction is Japanese ↔ English. All translation runs on-device on Apple Silicon;
no translation traffic leaves the machine.

The primary memory target is **8 GB unified memory**; 16 GB+ configurations are
also supported with more permissive residency. Inference uses **TranslateGemma-4B
(GGUF Q4_K_M)** on a llama.cpp / Metal runtime, with a capability-gated fallback to
Apple's on-device **Translation framework** when the app is under memory pressure.

Detailed design lives under `docs/`. Start with @docs/architecture.md and the ADRs
in @docs/decisions/.

## Project Structure

> **Open decision — implementation language is not yet fixed** (Swift/SwiftUI vs.
> a Rust core behind a thin Swift shell vs. Tauri). The layout below is tentative
> and will be pinned by a toolchain ADR before implementation starts.

```
src/         # app + runtime glue (language TBD)
docs/        # architecture, ADRs (docs/decisions/), validation notes
docs/decisions/  # ADRs — settled engineering judgements (English-only)
tests/       # TDD suite
```

## Development Setup

> Toolchain pins are **TBD** pending the language decision. Fill this in with the
> concrete bootstrap once the toolchain ADR lands.

```bash
# Pre-push hook (format / lint / clippy). Auto-detects Cargo.toml / package.json.
cp git-hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
# or: git config core.hooksPath git-hooks
```

## Build & Test

> **TBD** — canonical build/test commands land with the toolchain ADR. The common
> TDD rule below applies regardless of language.

## Development Principles

- **Local-only invariant.** Nothing on the translation path may make a network call.
- **Weights are a managed resident resource.** Residency and eviction follow
  `docs/decisions/0003-residency-and-eviction-policy.md` and
  `docs/decisions/0004-thrash-avoidance.md`, not ad-hoc lifetimes.
- **Settled engineering decisions require an ADR** in `docs/decisions/`.

## Architectural Boundaries

- Memory-pressure state (`Normal` / `Warn` / `Critical`) is an **orthogonal domain**.
  It is never linearised into the weight-lifecycle state machine (ADR 0005).
- **Eviction reacts to pressure/timeout; loading reacts only to user intent** — this
  asymmetry is what removes evict↔load oscillation (ADR 0004). Do not add a path that
  loads weights in response to a pressure event.
- The OS Translation-framework fallback is entered **only through the capability gate**
  (ADR 0006). Never assume the framework or its ja↔en model is available.

## Prohibitions

1. Do not introduce a network call on the translation path (local-only invariant).
2. Do not add per-token weight streaming for the Dense model (rejected — ADR 0002).
3. Do not couple pressure level into the weight-lifecycle enum (ADR 0005).
4. Do not trigger a weight load from a pressure transition (ADR 0004).

## Git Conventions

- Conventional Commits. Add project scopes (e.g. `feat(runtime):`) as they emerge.
- Engineering docs and every `docs/decisions/*.md` ADR are **English-only**
  (`docs/i18n-policy.md`). `README.md` may carry a `README.ja.md` twin.


---

<!-- Common rules below this line apply to every project. -->

## Common Development Rules

### TDD (Red → Green → Refactor)

All implementation work proceeds in this cycle:

1. **Red**: write a failing test that captures the intended behaviour.
2. **Green**: write the minimum code that makes the test pass.
3. **Refactor**: tidy up while keeping tests green.

When a test fails, fix the production code — do not delete, skip, or weaken the test.

### Git Conventions

- **Conventional Commits**: `feat:` `fix:` `docs:` `refactor:` `test:` `ci:` `chore:`. Project-specific prefixes (e.g. `data:`, `experiments:`) live in the project's `AGENTS.md`.
- **Branch naming**: use a short prefix for the agent or author followed by a topic, e.g. `claude/<topic>`, `codex/<topic>`, or `human/<topic>`.
- **Trailer**: when an AI agent authors the commit, append a trailer crediting the agent. Do not embed model name or session info in the trailer; put those in the commit body if needed.
- **Pre-push hook**: install via `cp git-hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push` (or `git config core.hooksPath git-hooks`). The hook runs format / lint / clippy before every push. Tests are intentionally omitted — TDD keeps them green at commit time.

### Pull Requests

- **Always ready for review.** Open PRs in the "ready" state, never as drafts. Draft PRs do not fire review-requested events and slow the loop.
- **Auto-subscribe after creating a PR.** Immediately after the PR is created, subscribe to its activity without asking the user. Rationale: the user explicitly opted into the "agent opens and watches its own PRs" workflow at the template level, so the per-PR confirmation is noise. Unsubscribe only when the user says to stop, when the PR merges, or when it is closed unmerged.
- **One PR per workstream**, matching the handoff issue. Reference the issue with `Closes #N` per `.github/PULL_REQUEST_TEMPLATE.md`.

### Stream Idle Timeout Mitigation

Cloud agent sessions occasionally fail with `Stream idle timeout - partial response received` on long output. To reduce risk:

1. **Stage long writes.** For long documents or source files, write the skeleton (headings, function signatures, trait stubs) first, then fill each section in follow-up edits. Avoid single blocks larger than ~200 lines.
2. **Watch out after large reads.** Reading a big file (e.g. `Cargo.lock`, large generated modules) and then immediately producing long output is a common trigger. Split into separate turns or excerpt only the relevant portion.
3. **Recover carefully.** A timeout can still leave the file write completed. Run `git status` before retrying so the same content is not written twice.

### Common Prohibitions

1. Do not delete, skip, or comment out existing tests.
2. Do not modify CI configuration without explicit instruction.
3. Do not weaken production code merely to make tests pass.
4. Do not commit credentials, API keys, signed URLs, or anything in `.env*`.
