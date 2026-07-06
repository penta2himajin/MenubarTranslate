import Testing
@testable import MenubarTranslateCore

@Suite("WeightLifecycle — Domain A state machine")
struct WeightLifecycleTests {
    @Test("starts unloaded")
    func initialState() {
        #expect(WeightLifecycle().state == .unloaded)
    }

    @Test("load path: unloaded → loading → ready")
    func loadPath() throws {
        var lc = WeightLifecycle()
        try lc.apply(.loadRequested)
        #expect(lc.state == .loading)
        try lc.apply(.loadCompleted)
        #expect(lc.state == .ready)
    }

    @Test("load failure returns to unloaded")
    func loadFailure() throws {
        var lc = WeightLifecycle()
        try lc.apply(.loadRequested)
        try lc.apply(.loadFailed)
        #expect(lc.state == .unloaded)
    }

    @Test("inference path: ready → inferring → ready")
    func inferPath() throws {
        var lc = WeightLifecycle(state: .ready)
        try lc.apply(.inferStarted)
        #expect(lc.state == .inferring)
        try lc.apply(.inferFinished)
        #expect(lc.state == .ready)
    }

    @Test("eviction path: ready → evicting → unloaded")
    func evictPath() throws {
        var lc = WeightLifecycle(state: .ready)
        try lc.apply(.evictRequested)
        #expect(lc.state == .evicting)
        try lc.apply(.evictCompleted)
        #expect(lc.state == .unloaded)
    }

    @Test("illegal: infer from unloaded throws")
    func illegalInferFromUnloaded() {
        var lc = WeightLifecycle()
        #expect(throws: IllegalTransition.self) { try lc.apply(.inferStarted) }
    }

    @Test("illegal: evict from unloaded throws")
    func illegalEvictFromUnloaded() {
        var lc = WeightLifecycle()
        #expect(throws: IllegalTransition.self) { try lc.apply(.evictRequested) }
    }

    @Test("illegal: load while inferring throws")
    func illegalLoadWhileInferring() {
        var lc = WeightLifecycle(state: .inferring)
        #expect(throws: IllegalTransition.self) { try lc.apply(.loadRequested) }
    }

    @Test("illegal: infer while loading throws")
    func illegalInferWhileLoading() {
        var lc = WeightLifecycle(state: .loading)
        #expect(throws: IllegalTransition.self) { try lc.apply(.inferStarted) }
    }

    @Test("canApply agrees with apply")
    func canApplyAgrees() {
        let lc = WeightLifecycle(state: .ready)
        #expect(lc.canApply(.inferStarted))
        #expect(lc.canApply(.evictRequested))
        #expect(!lc.canApply(.loadRequested))
    }
}
