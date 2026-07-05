-- core.als
-- Core domain model for MenubarTranslate. Single source of truth for the
-- weight-lifecycle x pressure state matrix (docs/architecture.md, ADRs 0003-0006).
-- English-only per docs/i18n-policy.md. Regenerate Swift with:
--   oxidtr generate models/core.als --target swift --output src/Core
--   oxidtr check --model models/core.als --impl src/Core   # CI gate

-- Weight lifecycle (ADR 0005). Orthogonal to pressure; never linearised together.
abstract sig WeightState {}
one sig Unloaded  extends WeightState {}
one sig Loading   extends WeightState {}
one sig Ready     extends WeightState {}
one sig Inferring extends WeightState {}
one sig Evicting  extends WeightState {}

-- Memory pressure (ADR 0005). Warn is debounced; Critical is immediate.
abstract sig PressureLevel {}
one sig Normal   extends PressureLevel {}
one sig Warn     extends PressureLevel {}
one sig Critical extends PressureLevel {}

-- Installed-RAM tier: only sets the initial residency preset (ADR 0003).
abstract sig RamTier {}
one sig Ram8GB  extends RamTier {}
one sig Ram16GB extends RamTier {}

-- Translation direction (primary JA<->EN).
abstract sig Direction {}
one sig JaToEn extends Direction {}
one sig EnToJa extends Direction {}

-- Inference backend: llama.cpp/Metal primary (ADR 0001),
-- OS Translation framework as capability-gated fallback (ADR 0006).
abstract sig Backend {}
one sig LlamaMetal    extends Backend {}
one sig OSTranslation extends Backend {}

-- Tri-state avoided: a plain yes/no flag. Named Flag (not Bool) so the Swift
-- target emits a real enum instead of colliding with the built-in Bool.
abstract sig Flag {}
one sig Yes extends Flag {}
one sig No  extends Flag {}

-- The level x state matrix (ADR 0005): two orthogonal domains held together.
sig Runtime {
  weight:   one WeightState,
  pressure: one PressureLevel,
  tier:     one RamTier,
  backend:  one Backend
}

-- Capability gate for the OS Translation fallback (ADR 0006):
-- API present AND ja<->en supported AND OS model already downloaded.
sig CapabilityGate {
  apiPresent:      one Flag,
  jaEnSupported:   one Flag,
  modelDownloaded: one Flag
}

sig TranslationRequest {
  direction: one Direction,
  source:    one Str
}

sig TranslationResult {
  request: one TranslationRequest,
  output:  one Str,
  backend: one Backend
}

-- Eviction reacts to pressure/timeout; loading reacts to user intent only (ADR 0004).
pred canEvict[r: Runtime] {
  r.weight = Ready or r.weight = Inferring
}

-- Fallback is entered only through the gate (ADR 0006).
pred fallbackAvailable[g: CapabilityGate] {
  g.apiPresent = Yes and g.jaEnSupported = Yes and g.modelDownloaded = Yes
}

fun activeBackend[r: Runtime]: one Backend { r.backend }

-- Critical pressure must not leave weights mid-inference (ADR 0004: immediate evict).
assert CriticalNotInferring {
  all r: Runtime | r.pressure = Critical implies r.weight != Inferring
}
