abstract sig WeightState {
}

sig Unloaded extends WeightState {
}

sig Loading extends WeightState {
}

sig Ready extends WeightState {
}

sig Inferring extends WeightState {
}

sig Evicting extends WeightState {
}

abstract sig PressureLevel {
}

sig Normal extends PressureLevel {
}

sig Warn extends PressureLevel {
}

sig Critical extends PressureLevel {
}

abstract sig RamTier {
}

sig Ram8GB extends RamTier {
}

sig Ram16GB extends RamTier {
}

abstract sig Direction {
}

sig JaToEn extends Direction {
}

sig EnToJa extends Direction {
}

abstract sig Backend {
}

sig LlamaMetal extends Backend {
}

sig OSTranslation extends Backend {
}

abstract sig Flag {
}

sig Yes extends Flag {
}

sig No extends Flag {
}

sig Runtime {
  weight: one WeightState,
  pressure: one PressureLevel,
  tier: one RamTier,
  backend: one Backend
}

sig CapabilityGate {
  apiPresent: one Flag,
  jaEnSupported: one Flag,
  modelDownloaded: one Flag
}

sig TranslationRequest {
  direction: one Direction,
  source: one String
}

sig TranslationResult {
  request: one TranslationRequest,
  output: one String,
  backend: one Backend
}

abstract sig LifecycleEvent {
}

sig LoadRequested extends LifecycleEvent {
}

sig LoadCompleted extends LifecycleEvent {
}

sig LoadFailed extends LifecycleEvent {
}

sig InferStarted extends LifecycleEvent {
}

sig InferFinished extends LifecycleEvent {
}

sig EvictRequested extends LifecycleEvent {
}

sig EvictCompleted extends LifecycleEvent {
}

sig Transition {
  from: one WeightState,
  event: one LifecycleEvent,
  to: one WeightState
}

-- Fact candidates (review required)
-- [LOW] from: force unwrap (line 11)
-- fact { -- force unwrap (review) }

