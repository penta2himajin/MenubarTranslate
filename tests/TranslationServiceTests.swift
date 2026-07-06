import Testing
@testable import MenubarTranslateCore

private extension ResidencyConfig {
    static let test = ResidencyConfig(
        idleTimeout: .seconds(30),
        residencyFloor: .seconds(5),
        warnDebounce: .seconds(2)
    )
}

private struct Fixture {
    let clock = ManualClock()
    let pressure = FakePressureSource()
    let engine = FakeEngine()
    let networkGuard = NetworkGuard()
    let manager: ResidencyManager
    let service: TranslationService

    init() {
        manager = ResidencyManager(config: .test, clock: clock, pressureSource: pressure)
        service = TranslationService(engine: engine, residency: manager, networkGuard: networkGuard)
    }
}

@Suite("TranslationService — orchestration")
struct TranslationServiceTests {
    @Test("cold start loads, infers, and returns the lifecycle trace")
    func coldStart() async throws {
        let f = Fixture()
        let outcome = try await f.service.translate("こんにちは", .jaToEn)
        #expect(outcome.text == "[ja-en] こんにちは")
        #expect(outcome.trace.map(\.state) == [.loading, .ready, .inferring, .ready])
    }

    @Test("warm reuse within the floor does not reload")
    func warmReuse() async throws {
        let f = Fixture()
        _ = try await f.service.translate("a", .enToJa)
        let second = try await f.service.translate("b", .enToJa)
        #expect(!second.trace.contains { $0.event == .loadRequested })
        #expect(f.engine.calls.filter { $0 == .load }.count == 1)
    }

    @Test("under critical pressure the trace ends by evicting after use")
    func criticalEvictAfterUse() async throws {
        let f = Fixture()
        f.pressure.emit(.critical)
        let outcome = try await f.service.translate("x", .jaToEn)
        #expect(Array(outcome.trace.map(\.state).suffix(3)) == [.ready, .evicting, .unloaded])
        #expect(f.engine.calls.contains(.evict))
    }

    @Test("the translation path never contacts the network guard (local-only)")
    func localOnly() async throws {
        let f = Fixture()
        _ = try await f.service.translate("hello", .enToJa)
        #expect(f.networkGuard.wasContacted == false)
    }
}

@Suite("Direction parsing")
struct DirectionParsingTests {
    @Test("parses the supported pairs")
    func parsesPairs() throws {
        #expect(try Direction.parse("ja-en") == .jaToEn)
        #expect(try Direction.parse("en-ja") == .enToJa)
    }

    @Test("rejects unknown tokens")
    func rejectsGarbage() {
        #expect(throws: DirectionParseError.self) {
            _ = try Direction.parse("fr-en")
        }
    }
}
