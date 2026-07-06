// WRITE-LOCKED — Wave 2 llama.cpp engine tests (author: Sonnet).
// These tests encode the exact public contract for MTEngineLlama real inference.
// Do NOT delete, skip, weaken assertions, or change expected values.
// Compile-level fixes (renames, import changes) must be reported.
// Lock copy: .devloop/locks/EngineLlamaTests.swift

import Testing
import Foundation
@testable import MenubarTranslateCore
import MTEngineLlama

// MARK: - Gating helpers

private func present(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

/// vendor/llama.xcframework present → real engine is compiled in.
private let vendorPresent: Bool = present("vendor/llama.xcframework")

private let ggufPath: String =
    ProcessInfo.processInfo.environment["MBT_LLAMA_GGUF"]
        ?? "models/weights/translategemma-4b-it-Q4_K_M.gguf"

/// Hy-MT2 GGUF path.  nil ⇒ gated Hy-MT2 tests disabled.
private let hymtGguf: String? =
    ProcessInfo.processInfo.environment["MBT_LLAMA_HYMT_GGUF"]

// MARK: - Suite

@Suite("MTEngineLlama — Wave 2", .serialized)
struct EngineLlamaTests {

    // ── (1) Ungated: error contracts ─────────────────────────────────────────
    // Must pass on a clean checkout (no xcframework, no weights).
    // The assertion is valid in BOTH states:
    //   • unvendored:  throws .unavailable("model file not found …")
    //   • vendored + no file: throws .unavailable("model file not found …")
    //   • vendored + file missing: same
    // We only assert .unavailable with a non-empty message — we do NOT pin the
    // exact text so both the stub and the real engine satisfy the test.

    @Test("load on nonexistent path throws .unavailable with non-empty message")
    func loadNonexistentPath() async {
        let engine = LlamaEngine(modelPath: "/nonexistent-\(UUID()).gguf")
        do {
            try await engine.load()
            Issue.record("expected TranslationEngineError.unavailable to be thrown")
        } catch TranslationEngineError.unavailable(let msg) {
            #expect(!msg.isEmpty, "error message must be non-empty")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("translate before load throws .notLoaded")
    func translateBeforeLoad() async {
        let engine = LlamaEngine(modelPath: "/nonexistent.gguf")
        await #expect(throws: TranslationEngineError.notLoaded) {
            _ = try await engine.translate("こんにちは", .jaToEn)
        }
    }

    // ── (2) Gated (vendorPresent && gguf exists): TranslateGemma inference ──
    // RED until xcframework is vendored AND weights present.

    @Test(
        "TranslateGemma: load succeeds",
        .enabled(if: vendorPresent && present(ggufPath))
    )
    func gemmaLoad() async throws {
        let engine = LlamaEngine(modelPath: ggufPath)
        try await engine.load()
    }

    @Test(
        "TranslateGemma: translate returns non-empty English without template artifacts",
        .enabled(if: vendorPresent && present(ggufPath))
    )
    func gemmaTranslate() async throws {
        let engine = LlamaEngine(modelPath: ggufPath)
        try await engine.load()
        let result = try await engine.translate("こんにちは。今日はいい天気ですね。", .jaToEn)
        #expect(!result.isEmpty, "translation must be non-empty")
        #expect(
            result.unicodeScalars.contains(where: { $0.value >= 65 && $0.value <= 122 }),
            "translation must contain ASCII letters (English); got: \(result.debugDescription)"
        )
        #expect(!result.contains("<start_of_turn>"),
                "must not contain <start_of_turn>; got: \(result.debugDescription)")
        #expect(!result.contains("<end_of_turn>"),
                "must not contain <end_of_turn>; got: \(result.debugDescription)")
        #expect(!result.contains("<|startoftext|>"),
                "must not contain <|startoftext|>; got: \(result.debugDescription)")
        #expect(!result.contains("<|extra_0|>"),
                "must not contain <|extra_0|>; got: \(result.debugDescription)")
    }

    @Test(
        "TranslateGemma: second translate on same engine works (M-invariance)",
        .enabled(if: vendorPresent && present(ggufPath))
    )
    func gemmaSecondTranslate() async throws {
        let engine = LlamaEngine(modelPath: ggufPath)
        try await engine.load()
        _ = try await engine.translate("こんにちは。", .jaToEn)
        let result2 = try await engine.translate("ありがとう。", .jaToEn)
        #expect(!result2.isEmpty, "second translation must be non-empty")
    }

    @Test(
        "TranslateGemma: evict → load → translate round-trip works (weight-level residency)",
        .enabled(if: vendorPresent && present(ggufPath))
    )
    func gemmaResidencyRoundTrip() async throws {
        let engine = LlamaEngine(modelPath: ggufPath)
        try await engine.load()
        await engine.evict()
        try await engine.load()
        let result = try await engine.translate("おはよう。", .jaToEn)
        #expect(!result.isEmpty, "translate after evict+reload must be non-empty")
    }

    // ── (3) Gated (vendorPresent && hymtGguf set && exists): Hy-MT2 GGUF ───
    // RED until MBT_LLAMA_HYMT_GGUF is set and the file exists.

    @Test(
        "HyMT2 GGUF: load+translate ja→en non-empty without hunyuan artifacts",
        .enabled(if: vendorPresent && hymtGguf != nil && present(hymtGguf ?? ""))
    )
    func hymtGgufInference() async throws {
        let path = hymtGguf!
        let engine = LlamaEngine(modelPath: path)
        try await engine.load()
        let result = try await engine.translate("こんにちは。今日はいい天気ですね。", .jaToEn)
        #expect(!result.isEmpty, "translation must be non-empty")
        #expect(!result.contains("<|extra_0|>"),
                "must not contain <|extra_0|>; got: \(result.debugDescription)")
        #expect(!result.contains("<|startoftext|>"),
                "must not contain <|startoftext|>; got: \(result.debugDescription)")
    }

    // ── (4) Gated CLI e2e (vendorPresent && gguf): CommandLineDriver + llama ─

    @Test(
        "CLI --engine llama with real llama factory translates and exits 0",
        .enabled(if: vendorPresent && present(ggufPath))
    )
    func cliLlamaE2E() async {
        let out = StringSink()
        let err = StringSink()
        let code = await CommandLineDriver().run(
            ["--dir", "ja-en", "--engine", "llama", "こんにちは"],
            stdin: nil,
            out: out,
            err: err,
            engineFactories: [
                "llama": { path in LlamaEngine(modelPath: path) }
            ]
        )
        #expect(code == 0,
                "exit code must be 0; stderr: \(err.buffer.debugDescription)")
        #expect(
            !out.buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "stdout must contain non-empty translation; got: \(out.buffer.debugDescription)"
        )
    }

    // ── (5) Ungated PromptBuilder unit tests ─────────────────────────────────
    // These pin the canonical rendered prompts so MLX and llama cannot drift.
    // No xcframework or weights needed.

    @Test("PromptBuilder.gemma ja→en contains expected system message and turn markers")
    func promptBuilderGemmaJaEn() {
        let p = PromptBuilder.gemma(text: "こんにちは", pair: .jaToEn)
        #expect(p.contains("You are a professional Japanese (ja) to English (en) translator"),
                "must contain role description; got: \(p.debugDescription)")
        #expect(p.contains("<start_of_turn>user"), "must start user turn")
        #expect(p.contains("<end_of_turn>"), "must close user turn")
        #expect(p.contains("<start_of_turn>model"), "must open model turn")
        #expect(p.contains("こんにちは"), "must embed the source text")
        // The triple-newline separator before the text is part of the training format.
        #expect(p.contains("\n\n\n"), "must contain triple-newline separator")
    }

    @Test("PromptBuilder.gemma en→ja contains expected system message")
    func promptBuilderGemmaEnJa() {
        let p = PromptBuilder.gemma(text: "Hello", pair: .enToJa)
        #expect(p.contains("You are a professional English (en) to Japanese (ja) translator"))
    }

    @Test("PromptBuilder.hunyuan ja→en starts with <|startoftext|> and ends with <|extra_0|>")
    func promptBuilderHunyuanJaEn() {
        let p = PromptBuilder.hunyuan(text: "こんにちは", pair: .jaToEn)
        #expect(p.hasPrefix("<|startoftext|>"), "must start with BOS marker")
        #expect(p.hasSuffix("<|extra_0|>"), "must end with extra_0 (model turn opener)")
        #expect(p.contains("English"), "must mention target language name")
        #expect(p.contains("こんにちは"), "must embed the source text")
    }

    @Test("PromptBuilder.hunyuan en→ja uses correct targetName")
    func promptBuilderHunyuanEnJa() {
        let p = PromptBuilder.hunyuan(text: "Hello", pair: .enToJa)
        #expect(p.contains("Japanese"), "must mention Japanese as target")
    }
}
