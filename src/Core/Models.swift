import Foundation

enum WeightState: Equatable, Hashable, CaseIterable {
    case unloaded
    case loading
    case ready
    case inferring
    case evicting
}

enum PressureLevel: Equatable, Hashable, CaseIterable {
    case normal
    case warn
    case critical
}

enum RamTier: Equatable, Hashable, CaseIterable {
    case ram8GB
    case ram16GB
}

enum Direction: Equatable, Hashable, CaseIterable {
    case jaToEn
    case enToJa
}

enum Backend: Equatable, Hashable, CaseIterable {
    case llamaMetal
    case oSTranslation
}

enum Flag: Equatable, Hashable, CaseIterable {
    case yes
    case no
}

struct Runtime: Equatable {
    let weight: WeightState
    let pressure: PressureLevel
    let tier: RamTier
    let backend: Backend
}

struct CapabilityGate: Equatable {
    let apiPresent: Flag
    let jaEnSupported: Flag
    let modelDownloaded: Flag
}

struct TranslationRequest: Equatable {
    let direction: Direction
    let source: String
}

struct TranslationResult: Equatable {
    let request: TranslationRequest
    let output: String
    let backend: Backend
}

