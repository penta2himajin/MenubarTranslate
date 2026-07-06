import Testing
@testable import MenubarTranslateCore

@Suite("Operations — canEvict, fallbackAvailable, activeBackend")
struct OperationsTests {

    // MARK: canEvict

    @Test("canEvict true for .ready")
    func canEvictReady() {
        let r = Runtime(weight: .ready, pressure: .normal, tier: .ram8GB, backend: .llamaMetal)
        #expect(canEvict(r) == true)
    }

    @Test("canEvict true for .inferring")
    func canEvictInferring() {
        let r = Runtime(weight: .inferring, pressure: .normal, tier: .ram8GB, backend: .llamaMetal)
        #expect(canEvict(r) == true)
    }

    @Test("canEvict false for .unloaded")
    func canEvictUnloaded() {
        let r = Runtime(weight: .unloaded, pressure: .normal, tier: .ram8GB, backend: .llamaMetal)
        #expect(canEvict(r) == false)
    }

    @Test("canEvict false for .loading")
    func canEvictLoading() {
        let r = Runtime(weight: .loading, pressure: .normal, tier: .ram8GB, backend: .llamaMetal)
        #expect(canEvict(r) == false)
    }

    @Test("canEvict false for .evicting")
    func canEvictEvicting() {
        let r = Runtime(weight: .evicting, pressure: .normal, tier: .ram8GB, backend: .llamaMetal)
        #expect(canEvict(r) == false)
    }

    // MARK: fallbackAvailable — ADR-0006 three-layer gate

    @Test("fallbackAvailable true when all flags .yes")
    func fallbackAllYes() {
        let g = CapabilityGate(apiPresent: .yes, jaEnSupported: .yes, modelDownloaded: .yes)
        #expect(fallbackAvailable(g) == true)
    }

    @Test("fallbackAvailable false when apiPresent is .no")
    func fallbackApiPresentNo() {
        let g = CapabilityGate(apiPresent: .no, jaEnSupported: .yes, modelDownloaded: .yes)
        #expect(fallbackAvailable(g) == false)
    }

    @Test("fallbackAvailable false when jaEnSupported is .no")
    func fallbackJaEnSupportedNo() {
        let g = CapabilityGate(apiPresent: .yes, jaEnSupported: .no, modelDownloaded: .yes)
        #expect(fallbackAvailable(g) == false)
    }

    @Test("fallbackAvailable false when modelDownloaded is .no")
    func fallbackModelDownloadedNo() {
        let g = CapabilityGate(apiPresent: .yes, jaEnSupported: .yes, modelDownloaded: .no)
        #expect(fallbackAvailable(g) == false)
    }

    // MARK: activeBackend

    @Test("activeBackend returns .llamaMetal")
    func activeBackendLlama() {
        let r = Runtime(weight: .ready, pressure: .normal, tier: .ram8GB, backend: .llamaMetal)
        #expect(activeBackend(r) == .llamaMetal)
    }

    @Test("activeBackend returns .oSTranslation")
    func activeBackendOS() {
        let r = Runtime(weight: .ready, pressure: .normal, tier: .ram8GB, backend: .oSTranslation)
        #expect(activeBackend(r) == .oSTranslation)
    }
}
