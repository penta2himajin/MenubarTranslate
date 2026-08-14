import Foundation
import Testing
import MTEngineLlama
@testable import MenubarTranslateCore

private func present(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

private let vendorPresent = present("vendor/llama.xcframework")
private let ggufPath =
    ProcessInfo.processInfo.environment["MBT_LLAMA_GGUF"]
        ?? "models/weights/gemma-4-E2B_q4_0-it.gguf"

@Suite("LlamaEngine multi-sequence batch")
struct LlamaBatchTests {
    @Test(
        "translateMany of four short strings is faster than four serial translates",
        .enabled(if: vendorPresent && present(ggufPath))
    )
    func batchFasterThanSerial() async throws {
        let snippets = ["設定", "ダウンロード", "サポート", "プライバシー"]
        let engine = LlamaEngine(modelPath: ggufPath)
        try await engine.load()

        let serialStart = ContinuousClock.now
        var serialOut: [String] = []
        for text in snippets {
            serialOut.append(try await engine.translate(text, .jaToEn))
        }
        let serialMS = (ContinuousClock.now - serialStart).milliseconds

        let batchStart = ContinuousClock.now
        let batchOut = try await engine.translateMany(snippets.map { ($0, .jaToEn) })
        let batchMS = (ContinuousClock.now - batchStart).milliseconds

        FileHandle.standardError.write(
            Data("llama batch n=\(snippets.count) serial=\(serialMS)ms parallel=\(batchMS)ms\n".utf8)
        )
        #expect(serialOut.allSatisfy { !$0.isEmpty })
        #expect(batchOut.count == snippets.count)
        #expect(batchOut.allSatisfy { !$0.isEmpty })
        // Measured 2026-08-14 on this checkout: n=4 serial=922ms parallel=664ms.
        #expect(batchMS < serialMS)
    }
}

private extension Duration {
    var milliseconds: Int {
        let c = components
        return Int(c.seconds * 1000) + Int(c.attoseconds / 1_000_000_000_000_000)
    }
}
