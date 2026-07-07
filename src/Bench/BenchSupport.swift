import Foundation
import Darwin

// ── Sentences ──────────────────────────────────────────────────────────────

/// Hard-coded sentence set for the bench. Exactly 8 Japanese (kanji/kana) and 8
/// English entries, paired by index, varied across register (greeting, weather,
/// news, technical, business email, casual, long compound, numbers/dates).
public enum BenchSentences {
    public static let japanese: [String] = [
        "こんにちは、今日も一日頑張りましょう。",                          // greeting
        "今日は雨が降っていますが、明日は晴れるそうです。",                  // weather
        "政府は来年度の予算編成に向けた基本方針を閣議決定しました。",          // news
        "この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。",   // technical
        "お世話になっております。来週の会議の日程についてご相談があります。",   // business email
        "ちょっと手伝ってくれない？後でご飯行かない？",                       // casual
        "急速に進展する人工知能技術は社会の構造そのものを変容させつつある。",   // long compound
        "2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。",         // numbers/dates
    ]

    public static let english: [String] = [
        "Hello, let's do our best again today.",
        "It's raining today, but it's supposed to clear up tomorrow.",
        "The cabinet approved the basic policy for next fiscal year's budget drafting.",
        "This function enqueues an async task and invokes a callback on completion.",
        "I hope this message finds you well. I'd like to discuss next week's meeting schedule.",
        "Could you give me a hand? Wanna grab dinner later?",
        "Rapidly advancing artificial intelligence technology is transforming the very structure of society.",
        "On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1.",
    ]
}

// ── Stats ──────────────────────────────────────────────────────────────────

/// Nearest-rank percentile + mean helpers.
public enum BenchStats {
    /// Nearest-rank percentile: sort ascending, rank = ceil(fraction * n),
    /// index = rank - 1. Single-element input returns that element.
    private static func nearestRank(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let n = sorted.count
        let rank = Int((fraction * Double(n)).rounded(.up))
        let idx = max(0, min(n - 1, rank - 1))
        return sorted[idx]
    }

    public static func p50(_ values: [Double]) -> Double {
        nearestRank(values, fraction: 0.50)
    }

    public static func p95(_ values: [Double]) -> Double {
        nearestRank(values, fraction: 0.95)
    }

    public static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

// ── Result ─────────────────────────────────────────────────────────────────

/// A single config's measurement summary.
public struct BenchResult {
    public var name:           String
    public var coldLoadMS:     Double
    public var warmReloadMS:   Double
    public var loadedDeltaMB:  Double
    public var p50:            Double
    public var p95:            Double
    public var meanMS:         Double
    public var charsPerSec:    Double
    public var skippedReason:  String?  // nil = ran, non-nil = skipped

    public init(name: String, coldLoadMS: Double, warmReloadMS: Double,
                loadedDeltaMB: Double, p50: Double, p95: Double,
                meanMS: Double, charsPerSec: Double, skippedReason: String? = nil) {
        self.name = name
        self.coldLoadMS = coldLoadMS
        self.warmReloadMS = warmReloadMS
        self.loadedDeltaMB = loadedDeltaMB
        self.p50 = p50
        self.p95 = p95
        self.meanMS = meanMS
        self.charsPerSec = charsPerSec
        self.skippedReason = skippedReason
    }
}

// ── Formatter ──────────────────────────────────────────────────────────────

/// Markdown table renderer for a batch of `BenchResult`s.
public enum BenchFormatter {
    public static func markdownTable(_ results: [BenchResult]) -> String {
        var lines: [String] = []
        lines.append("| Config | Cold (ms) | Warm (ms) | ΔMB | p50 | p95 | mean | chars |")
        lines.append("|---|---|---|---|---|---|---|---|")
        for r in results {
            if let reason = r.skippedReason {
                lines.append("| \(r.name) | \(reason) | | | | | | |")
            } else {
                lines.append(String(
                    format: "| %@ | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |",
                    r.name,
                    r.coldLoadMS,
                    r.warmReloadMS,
                    r.loadedDeltaMB,
                    r.p50,
                    r.p95,
                    r.meanMS,
                    r.charsPerSec
                ))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// ── Config matrix ──────────────────────────────────────────────────────────

public struct BenchConfigEntry {
    public var name:          String
    public var artifactPath:  String
    public var skippedReason: String?  // nil = present; non-nil = skip this config
    public init(name: String, artifactPath: String, skippedReason: String? = nil) {
        self.name = name
        self.artifactPath = artifactPath
        self.skippedReason = skippedReason
    }
}

/// The five hard-coded bench configs. Default artifact paths are overridable via
/// the listed environment variables. `artifactExists` is injected for testability
/// (FileManager.default.fileExists in production).
///
/// When `only` is non-nil, configs whose name is not in the set are dropped
/// entirely (not merely marked skipped).
public func buildBenchConfigMatrix(
    artifactExists: (String) -> Bool,
    only: Set<String>? = nil
) -> [BenchConfigEntry] {
    let env = ProcessInfo.processInfo.environment

    let specs: [(name: String, defaultPath: String, envVar: String)] = [
        ("gemma-mlx",     "models/weights/translategemma-mlx",                "MBT_MLX_DIR"),
        ("hymt-1.8b-mlx", "models/weights/hy-mt2-1.8b-mlx-4bit",              "MBT_MLX_HYMT_DIR"),
        ("hymt-7b-mlx",   "models/weights/hy-mt2-7b-mlx-4bit",                "MBT_MLX_HYMT7B_DIR"),
        ("gemma-gguf",    "models/weights/translategemma-4b-it-Q4_K_M.gguf",  "MBT_LLAMA_GGUF"),
        ("hymt-7b-gguf",  "models/weights/Hy-MT2-7B-Q4_K_M.gguf",             "MBT_LLAMA_HYMT7B_GGUF"),
    ]

    var entries: [BenchConfigEntry] = []
    for spec in specs {
        if let only, !only.contains(spec.name) { continue }
        let path = env[spec.envVar] ?? spec.defaultPath
        if artifactExists(path) {
            entries.append(BenchConfigEntry(name: spec.name, artifactPath: path))
        } else {
            entries.append(BenchConfigEntry(
                name: spec.name,
                artifactPath: path,
                skippedReason: "artifact not found at \(path)"))
        }
    }
    return entries
}

// ── Physical footprint ─────────────────────────────────────────────────────

/// Samples the current process's `phys_footprint` via `task_info(TASK_VM_INFO)`.
/// Returns the value in MB. Returns 0.0 on failure.
public func samplePhysFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return 0.0 }
    let footprint = info.phys_footprint
    return Double(footprint) / (1024.0 * 1024.0)
}
