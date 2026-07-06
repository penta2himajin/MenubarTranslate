// WRITE-LOCKED — Wave 1 MLX engine tests (author: Sonnet).
// These tests encode the exact public contract for MTEngineMLX real inference.
// Do NOT delete, skip, weaken assertions, or change expected values.
// Compile-level fixes (renames, import changes) must be reported.
// Lock copy: .devloop/locks/EngineMLXTests.swift

import Testing
import Foundation
@testable import MenubarTranslateCore
import MTEngineMLX

// MARK: - Helpers

private func present(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

private let mlxGemmaDir: String =
    ProcessInfo.processInfo.environment["MBT_MLX_DIR"]
        ?? "models/weights/translategemma-mlx"

private let mlxHymtDir: String =
    ProcessInfo.processInfo.environment["MBT_MLX_HYMT_DIR"]
        ?? "models/weights/hy-mt2-1.8b-mlx-4bit"

// MARK: - Suite

/// Weight-gated tests use `.enabled(if:)` and are skipped (not failed) when the model
/// directory is absent, so plain `swift test` on a clean machine stays green.
/// `.serialized` prevents concurrent model loads from racing on the GPU.
@Suite("MLXEngine — Wave 1", .serialized)
struct EngineMLXTests {

    // ── (1) Ungated: error contracts ─────────────────────────────────────────
    // These must pass even without weights (stub already satisfies them).

    @Test("load on nonexistent directory throws .unavailable mentioning the path")
    func loadNonexistentDir() async {
        let path = "/nonexistent-mlx-\(UUID())"
        let engine = MLXEngine(modelDirectory: path)
        do {
            try await engine.load()
            Issue.record("expected TranslationEngineError.unavailable to be thrown")
        } catch TranslationEngineError.unavailable(let msg) {
            #expect(msg.contains(path), "error message must mention the model directory path")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("translate before load throws .notLoaded")
    func translateBeforeLoad() async {
        let engine = MLXEngine(modelDirectory: "/nonexistent")
        await #expect(throws: TranslationEngineError.notLoaded) {
            _ = try await engine.translate("こんにちは", .jaToEn)
        }
    }

    // ── (2) Gated on TranslateGemma dir: inference quality ──────────────────
    // RED with stub: load() throws .unavailable("not implemented yet") for existing dirs.

    @Test(
        "TranslateGemma: load succeeds; translate returns English output without template artifacts; second translate works",
        .enabled(if: present(mlxGemmaDir))
    )
    func gemmaInference() async throws {
        let engine = MLXEngine(modelDirectory: mlxGemmaDir)
        // load() must succeed without throwing.
        try await engine.load()

        // First translate — must produce English text.
        let result = try await engine.translate("こんにちは。今日はいい天気ですね。", .jaToEn)
        #expect(!result.isEmpty, "translation must be non-empty")
        // Must contain ASCII letters (English output).
        #expect(
            result.unicodeScalars.contains(where: { $0.value >= 65 && $0.value <= 122 }),
            "translation must contain ASCII letters (English); got: \(result.debugDescription)"
        )
        // Must not leak Gemma chat-template tokens.
        #expect(!result.contains("<start_of_turn>"),
                "output must not contain <start_of_turn>; got: \(result.debugDescription)")
        #expect(!result.contains("<end_of_turn>"),
                "output must not contain <end_of_turn>; got: \(result.debugDescription)")

        // M-invariance: second translate on the same loaded engine must also work
        // (KV/session state must not be corrupted between calls).
        let result2 = try await engine.translate("ありがとう。", .jaToEn)
        #expect(!result2.isEmpty,
                "second translation on same engine must be non-empty")
    }

    // ── (3) Gated on TranslateGemma dir: weight-level residency round-trip ──
    // RED with stub: load() throws before evict can be verified.

    @Test(
        "TranslateGemma: evict then reload then translate works (weight-level residency round-trip)",
        .enabled(if: present(mlxGemmaDir))
    )
    func gemmaResidencyRoundTrip() async throws {
        let engine = MLXEngine(modelDirectory: mlxGemmaDir)
        try await engine.load()
        // Evict must release GPU memory without crashing.
        await engine.evict()
        // Warm reload must succeed and leave engine fully operational.
        try await engine.load()
        let result = try await engine.translate("おはよう。", .jaToEn)
        #expect(!result.isEmpty,
                "translate after evict+reload must be non-empty")
    }

    // ── (4) Gated on Hy-MT2-1.8B dir: model-agnostic hunyuan prompt path ───
    // RED with stub: load() throws before inference path can be verified.

    @Test(
        "HyMT2-1.8B: load+translate ja→en returns non-empty without hunyuan template artifacts",
        .enabled(if: present(mlxHymtDir))
    )
    func hymtInference() async throws {
        let engine = MLXEngine(modelDirectory: mlxHymtDir)
        try await engine.load()
        let result = try await engine.translate("こんにちは。今日はいい天気ですね。", .jaToEn)
        #expect(!result.isEmpty, "translation must be non-empty")
        // Must not leak hunyuan special tokens into the output.
        #expect(!result.contains("<|extra_0|>"),
                "output must not contain <|extra_0|>; got: \(result.debugDescription)")
        #expect(!result.contains("<|startoftext|>"),
                "output must not contain <|startoftext|>; got: \(result.debugDescription)")
    }

    // ── (5) Gated CLI e2e: factory injection + full service path ────────────
    // RED with stub: load() throws; even if it didn't, the driver falls through to the
    // base run() which hard-rejects non-fake engines (Wave-0 reviewer gap).

    @Test(
        "CLI --engine mlx with real MLX factory translates and exits 0",
        .enabled(if: present(mlxGemmaDir))
    )
    func cliMLXE2E() async {
        let out = StringSink()
        let err = StringSink()
        let code = await CommandLineDriver().run(
            ["--dir", "ja-en", "--engine", "mlx", "こんにちは"],
            stdin: nil,
            out: out,
            err: err,
            engineFactories: [
                "mlx": { dir in MLXEngine(modelDirectory: dir) }
            ]
        )
        #expect(code == 0,
                "exit code must be 0; stderr: \(err.buffer.debugDescription)")
        #expect(
            !out.buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "stdout must contain non-empty translation; got: \(out.buffer.debugDescription)"
        )
    }
}
