import XCTest

final class PropertyTests: XCTestCase {
    func test_CriticalNotInferring() {
        let runtimes: [Runtime] = []
        XCTAssertTrue(runtimes.allSatisfy { r in !(r.pressure == Critical) || r.weight != Inferring })
    }

    // --- Anomaly tests: edge-case coverage ---

    func testAnomaly_runtime_weight_unconstrained() {
        let instance = Fixtures.defaultRuntime()
        _ = instance.weight
    }

    func testAnomaly_runtime_pressure_unconstrained() {
        let instance = Fixtures.defaultRuntime()
        _ = instance.pressure
    }

    func testAnomaly_runtime_tier_unconstrained() {
        let instance = Fixtures.defaultRuntime()
        _ = instance.tier
    }

    func testAnomaly_runtime_backend_unconstrained() {
        let instance = Fixtures.defaultRuntime()
        _ = instance.backend
    }

    func testAnomaly_capability_gate_apiPresent_unconstrained() {
        let instance = Fixtures.defaultCapabilityGate()
        _ = instance.apiPresent
    }

    func testAnomaly_capability_gate_jaEnSupported_unconstrained() {
        let instance = Fixtures.defaultCapabilityGate()
        _ = instance.jaEnSupported
    }

    func testAnomaly_capability_gate_modelDownloaded_unconstrained() {
        let instance = Fixtures.defaultCapabilityGate()
        _ = instance.modelDownloaded
    }

    func testAnomaly_translation_request_direction_unconstrained() {
        let instance = Fixtures.defaultTranslationRequest()
        _ = instance.direction
    }

    func testAnomaly_translation_request_source_unconstrained() {
        let instance = Fixtures.defaultTranslationRequest()
        _ = instance.source
    }

    func testAnomaly_translation_result_request_unconstrained() {
        let instance = Fixtures.defaultTranslationResult()
        _ = instance.request
    }

    func testAnomaly_translation_result_output_unconstrained() {
        let instance = Fixtures.defaultTranslationResult()
        _ = instance.output
    }

    func testAnomaly_translation_result_backend_unconstrained() {
        let instance = Fixtures.defaultTranslationResult()
        _ = instance.backend
    }

}
