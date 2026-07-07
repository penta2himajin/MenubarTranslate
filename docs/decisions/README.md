# Architecture Decision Records

Settled engineering judgements for MenubarTranslate. English-only per
`docs/i18n-policy.md`. Format: Context → Decision → Consequences → Alternatives.

| ADR | Title | Status |
|---|---|---|
| 0001 | Model selection: TranslateGemma-4B (GGUF Q4_K_M) | Superseded by 0008 |
| 0002 | Memory strategy: no per-token weight streaming | Accepted |
| 0003 | Residency and eviction policy | Accepted |
| 0004 | Thrash avoidance: asymmetric evict/load + hysteresis | Accepted |
| 0005 | Pressure as an orthogonal state-machine domain | Accepted |
| 0006 | Critical-pressure degradation and OS fallback | Accepted |
| 0007 | Toolchain: Swift + SwiftUI, native, via SwiftPM | Accepted |
| 0008 | Runtime selection: TranslateGemma-4B on MLX 4-bit (measured) | Accepted (amended: GGUF default) |

Several decisions depend on measurements that are **not yet done on real hardware**;
those are tracked in `docs/validation.md` and may reopen the relevant ADR.
