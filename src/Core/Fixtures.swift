import Foundation

/// Factory: default value for WeightState
func defaultWeightState() -> WeightState { .unloaded }

/// Factory: default value for PressureLevel
func defaultPressureLevel() -> PressureLevel { .normal }

/// Factory: default value for RamTier
func defaultRamTier() -> RamTier { .ram8GB }

/// Factory: default value for Direction
func defaultDirection() -> Direction { .jaToEn }

/// Factory: default value for Backend
func defaultBackend() -> Backend { .llamaMetal }

/// Factory: default value for Flag
func defaultFlag() -> Flag { .yes }

/// Factory: create a default valid Runtime
func defaultRuntime() -> Runtime {
    Runtime(
        weight: defaultWeightState(),
        pressure: defaultPressureLevel(),
        tier: defaultRamTier(),
        backend: defaultBackend()
    )
}

/// Factory: create a default valid CapabilityGate
func defaultCapabilityGate() -> CapabilityGate {
    CapabilityGate(
        apiPresent: defaultFlag(),
        jaEnSupported: defaultFlag(),
        modelDownloaded: defaultFlag()
    )
}

/// Factory: create a default valid TranslationRequest
func defaultTranslationRequest() -> TranslationRequest {
    TranslationRequest(
        direction: defaultDirection(),
        source: defaultStr()
    )
}

/// Factory: create a default valid TranslationResult
func defaultTranslationResult() -> TranslationResult {
    TranslationResult(
        request: defaultTranslationRequest(),
        output: defaultStr(),
        backend: defaultBackend()
    )
}

