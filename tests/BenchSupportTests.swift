// WRITE-LOCKED — Wave 3 bench-support tests (author: Sonnet).
// Tests the pure-Swift BenchSupport layer in src/Bench/ (part of MenubarTranslateCore).
// Do NOT delete, skip, weaken assertions, or change expected values.
// Compile-level fixes (renames, import changes) must be reported.
// Lock copy: .devloop/locks/BenchSupportTests.swift
//
// All tests are ungated (no model weights required). The bench itself is a tool;
// model-loading tests do not belong here.
//
// API contract required of the implementer (in src/Bench/):
//   public struct BenchResult { name, coldLoadMS, warmReloadMS, loadedDeltaMB,
//                               p50, p95, meanMS, charsPerSec, skippedReason: String? }
//   public enum BenchSentences { static let japanese: [String]; static let english: [String] }
//   public enum BenchStats    { static func p50/p95/mean(_ values: [Double]) -> Double }
//   public enum BenchFormatter { static func markdownTable(_ results: [BenchResult]) -> String }
//   public struct BenchConfigEntry { name: String; artifactPath: String; skippedReason: String? }
//   public func buildBenchConfigMatrix(artifactExists: (String) -> Bool,
//                                      only: Set<String>? = nil) -> [BenchConfigEntry]
//   public func samplePhysFootprintMB() -> Double   // via TASK_VM_INFO.phys_footprint

import Testing
import Foundation
@testable import MenubarTranslateCore

// MARK: - Test-local helper

/// Returns true when `s` contains at least one Hiragana, Katakana, or CJK Unified Ideograph
/// scalar — a proxy for "this string is Japanese".
private func containsCJK(_ s: String) -> Bool {
    s.unicodeScalars.contains {
        ($0.value >= 0x3040 && $0.value <= 0x30FF) ||  // Hiragana + Katakana
        ($0.value >= 0x4E00 && $0.value <= 0x9FFF)     // CJK Unified Ideographs
    }
}

// MARK: - Suite

@Suite("BenchSupport — Wave 3 locked")
struct BenchSupportTests {

    // ── (1) Sentence set: size, non-empty, and count invariance ──────────────
    // M-invariance: JA.count == EN.count because sentences are paired by index.
    // Both arrays must be non-empty (empty strings would produce zero-length translations
    // and corrupt chars/s metrics).

    @Test("sentence set has exactly 8 JA and 8 EN entries, all non-empty, counts equal")
    func sentenceSetSizeAndNonEmpty() {
        let ja = BenchSentences.japanese
        let en = BenchSentences.english
        #expect(ja.count == 8, "expected exactly 8 Japanese sentences; got \(ja.count)")
        #expect(en.count == 8, "expected exactly 8 English sentences; got \(en.count)")
        #expect(ja.count == en.count, "JA and EN sentence counts must be equal (paired by index)")
        for (i, s) in ja.enumerated() {
            #expect(!s.isEmpty, "japanese[\(i)] must be non-empty")
        }
        for (i, s) in en.enumerated() {
            #expect(!s.isEmpty, "english[\(i)] must be non-empty")
        }
    }

    // ── (2) Sentence set: language invariant ─────────────────────────────────
    // RED check: swapping a JA for EN (or vice-versa) would silently produce wrong-direction
    // prompts, so both polarities are verified.

    @Test("JA entries contain CJK; EN entries do not (language invariant)")
    func sentenceSetLanguageInvariant() {
        for (i, s) in BenchSentences.japanese.enumerated() {
            #expect(containsCJK(s),
                    "japanese[\(i)] must contain a CJK/kana character; got: \(s.debugDescription)")
        }
        for (i, s) in BenchSentences.english.enumerated() {
            #expect(!containsCJK(s),
                    "english[\(i)] must not contain CJK/kana characters; got: \(s.debugDescription)")
        }
    }

    // ── (3) Stats: odd-length array ───────────────────────────────────────────
    // [1,2,3,4,5] sorted. Nearest-rank formula: rank = ceil(f * n), index = rank - 1.
    //   p50 → ceil(0.50 * 5) = 3 → index 2 → 3.0
    //   p95 → ceil(0.95 * 5) = 5 → index 4 → 5.0
    //   mean = 15/5 = 3.0
    // Also verifies that an unsorted input is sorted before computing (adversarial order).

    @Test("stats p50/p95/mean on 5-element unsorted array give correct values")
    func statsOddLength() {
        let values = [3.0, 1.0, 4.0, 2.0, 5.0]  // deliberately unsorted
        #expect(BenchStats.p50(values) == 3.0,
                "p50([1,2,3,4,5]) must be 3.0; got \(BenchStats.p50(values))")
        #expect(BenchStats.p95(values) == 5.0,
                "p95([1,2,3,4,5]) must be 5.0; got \(BenchStats.p95(values))")
        #expect(BenchStats.mean(values) == 3.0,
                "mean([1,2,3,4,5]) must be 3.0; got \(BenchStats.mean(values))")
    }

    // ── (4) Stats: even-length array ─────────────────────────────────────────
    // [2,4,6,8] sorted. Nearest-rank:
    //   p50 → ceil(0.50 * 4) = 2 → index 1 → 4.0
    //   p95 → ceil(0.95 * 4) = 4 → index 3 → 8.0
    //   mean = 20/4 = 5.0

    @Test("stats p50/p95/mean on 4-element array give correct values")
    func statsEvenLength() {
        let values = [2.0, 4.0, 6.0, 8.0]
        #expect(BenchStats.p50(values) == 4.0,
                "p50([2,4,6,8]) must be 4.0; got \(BenchStats.p50(values))")
        #expect(BenchStats.p95(values) == 8.0,
                "p95([2,4,6,8]) must be 8.0; got \(BenchStats.p95(values))")
        #expect(BenchStats.mean(values) == 5.0,
                "mean([2,4,6,8]) must be 5.0; got \(BenchStats.mean(values))")
    }

    // ── (5) Stats: single-element adversarial ────────────────────────────────
    // p50, p95, and mean of a single-element array must all equal that element.

    @Test("stats on single-element array return that element for p50, p95, and mean")
    func statsSingleElement() {
        let values = [42.0]
        #expect(BenchStats.p50(values)  == 42.0)
        #expect(BenchStats.p95(values)  == 42.0)
        #expect(BenchStats.mean(values) == 42.0)
    }

    // ── (6) Markdown table: header row ───────────────────────────────────────

    @Test("markdownTable output contains required column headers")
    func markdownTableHeaderRow() {
        let table = BenchFormatter.markdownTable([])
        // Must have a header row with at minimum these landmarks.
        #expect(table.contains("Config"),  "table must have a 'Config' column header")
        #expect(table.contains("Cold"),    "table must have a cold-load column header")
        #expect(table.contains("p50"),     "table must have a 'p50' column header")
        #expect(table.contains("p95"),     "table must have a 'p95' column header")
        #expect(table.contains("chars"),   "table must have a throughput (chars) column header")
        // Markdown table separator row (---|---).
        #expect(table.contains("---"),     "table must contain a markdown separator row")
    }

    // ── (7) Markdown table: non-skipped row ──────────────────────────────────
    // Numbers must appear formatted to 1 decimal place.

    @Test("markdownTable row for a running config contains name and 1-decimal numbers")
    func markdownTableRunRow() {
        let result = BenchResult(
            name: "gemma-mlx",
            coldLoadMS:    1200.5,
            warmReloadMS:   480.3,
            loadedDeltaMB: 3200.0,
            p50:   15.7,
            p95:   42.1,
            meanMS: 18.3,
            charsPerSec: 88.4
        )
        let table = BenchFormatter.markdownTable([result])
        #expect(table.contains("gemma-mlx"), "row must contain the config name")
        // Verify 1-decimal formatting by checking the exact expected string.
        #expect(table.contains(String(format: "%.1f", result.coldLoadMS)),
                "cold-load must appear as '\(String(format: "%.1f", result.coldLoadMS))'")
        #expect(table.contains(String(format: "%.1f", result.p50)),
                "p50 must appear as '\(String(format: "%.1f", result.p50))'")
        #expect(table.contains(String(format: "%.1f", result.charsPerSec)),
                "charsPerSec must appear as '\(String(format: "%.1f", result.charsPerSec))'")
    }

    // ── (8) Markdown table: skipped row ──────────────────────────────────────

    @Test("markdownTable row for a skipped config contains name and skip reason")
    func markdownTableSkippedRow() {
        let result = BenchResult(
            name: "hymt-7b-gguf",
            coldLoadMS: 0, warmReloadMS: 0, loadedDeltaMB: 0,
            p50: 0, p95: 0, meanMS: 0, charsPerSec: 0,
            skippedReason: "artifact not found at expected path"
        )
        let table = BenchFormatter.markdownTable([result])
        #expect(table.contains("hymt-7b-gguf"),
                "skipped row must contain the config name")
        #expect(table.contains("artifact not found at expected path"),
                "skipped row must contain the skip reason")
    }

    // ── (9) Physical footprint sampler: positive baseline ────────────────────

    @Test("samplePhysFootprintMB returns a positive value at baseline")
    func physFootprintPositive() {
        let footprint = samplePhysFootprintMB()
        #expect(footprint > 0, "phys_footprint must be positive; got \(footprint)")
    }

    // ── (10) Physical footprint sampler: increases after large allocation ─────
    // Allocates ~200 MB of non-zero bytes (forcing physical page backing) and asserts
    // the sampled delta exceeds 100 MB. This validates the TASK_VM_INFO plumbing
    // end-to-end without any model dependency.

    @Test("samplePhysFootprintMB increases by >100 MB after a ~200 MB allocation")
    func physFootprintIncreasesAfterAlloc() {
        let baseline = samplePhysFootprintMB()
        // Non-zero fill forces physical page allocation (avoids lazy-zero optimisation).
        let blob = Data(repeating: 0xAB, count: 200 * 1024 * 1024)
        let afterAlloc = samplePhysFootprintMB()
        _ = blob[0]  // ensure blob is live through the measurement
        #expect(afterAlloc - baseline > 100,
                "footprint must grow by >100 MB; baseline=\(baseline) after=\(afterAlloc)")
    }

    // ── (11) Config matrix: missing artifacts produce skipped entries ─────────
    // The matrix is hard-coded to 5 configs; all yield a non-nil skippedReason when
    // the existence closure always returns false.

    @Test("buildBenchConfigMatrix with all missing artifacts yields 5 skipped entries")
    func configMatrixAllMissingSkipped() {
        let configs = buildBenchConfigMatrix(artifactExists: { _ in false })
        #expect(configs.count == 5,
                "matrix must contain exactly 5 configs; got \(configs.count)")
        for cfg in configs {
            #expect(cfg.skippedReason != nil,
                    "config '\(cfg.name)' must be skipped when its artifact is absent")
            #expect(!(cfg.skippedReason ?? "").isEmpty,
                    "skippedReason for '\(cfg.name)' must be non-empty")
        }
    }

    // ── (12) Config matrix: --only filter ────────────────────────────────────
    // When only = ["gemma-mlx"] and all artifacts are present, exactly one entry
    // is returned and it is not skipped.

    @Test("buildBenchConfigMatrix with --only filter returns the named subset")
    func configMatrixOnlyFilter() {
        let configs = buildBenchConfigMatrix(
            artifactExists: { _ in true },
            only: ["gemma-mlx"]
        )
        #expect(configs.count == 1,
                "--only [\"gemma-mlx\"] must return exactly 1 entry; got \(configs.count)")
        #expect(configs[0].name == "gemma-mlx",
                "filtered entry must be named 'gemma-mlx'; got '\(configs[0].name)'")
        #expect(configs[0].skippedReason == nil,
                "'gemma-mlx' must not be skipped when artifact is present")
    }
}
