import Foundation
import MenubarTranslateCore
import MTEngineLlama
import MTEngineMLX

#if canImport(Darwin)
import Darwin
#endif

// ── CLI args ────────────────────────────────────────────────────────────────

var onlySet: Set<String> = []
var outPath: String? = nil

let cliArgs = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < cliArgs.count {
    let a = cliArgs[i]
    switch a {
    case "--only":
        i += 1
        if i < cliArgs.count { onlySet.insert(cliArgs[i]) }
    case "--out":
        i += 1
        if i < cliArgs.count { outPath = cliArgs[i] }
    default:
        FileHandle.standardError.write(Data("--only <name> (repeatable), --out <path>\n".utf8))
    }
    i += 1
}

let only: Set<String>? = onlySet.isEmpty ? nil : onlySet

// ── Build config matrix ───────────────────────────────────────────────────

let configs = buildBenchConfigMatrix(
    artifactExists: { FileManager.default.fileExists(atPath: $0) },
    only: only
)

// ── Engine factory ─────────────────────────────────────────────────────────

func makeEngine(for name: String, path: String) -> any TranslationEngine {
    switch name {
    case "gemma-mlx", "hymt-1.8b-mlx", "hymt-7b-mlx":
        return MLXEngine(modelDirectory: path)
    case "gemma-gguf", "hymt-7b-gguf":
        return LlamaEngine(modelPath: path)
    default:
        return LlamaEngine(modelPath: path)
    }
}

func elapsed(_ start: Date) -> Double {
    Date().timeIntervalSince(start)
}

// ── Per-config measurement ────────────────────────────────────────────────

struct Transcript {
    var jaEn: [(String, String)] = []   // (source, output)
    var enJa: [(String, String)] = []
}

func measureConfig(_ entry: BenchConfigEntry) async -> (BenchResult, Transcript) {
    var transcript = Transcript()

    // If the matrix already marked it skipped (artifact absent), propagate.
    if let reason = entry.skippedReason {
        return (BenchResult(
            name: entry.name,
            coldLoadMS: 0, warmReloadMS: 0, loadedDeltaMB: 0,
            p50: 0, p95: 0, meanMS: 0, charsPerSec: 0,
            skippedReason: reason), transcript)
    }

    let engine = makeEngine(for: entry.name, path: entry.artifactPath)
    let baselineMB = samplePhysFootprintMB()

    // Cold load
    let coldStart = Date()
    do {
        try await engine.load()
    } catch {
        return (BenchResult(
            name: entry.name,
            coldLoadMS: 0, warmReloadMS: 0, loadedDeltaMB: 0,
            p50: 0, p95: 0, meanMS: 0, charsPerSec: 0,
            skippedReason: "cold load failed: \(error)"), transcript)
    }
    let coldLoadMS = elapsed(coldStart) * 1000
    let loadedDeltaMB = samplePhysFootprintMB() - baselineMB

    // 16 translate calls: first 8 JA→EN, then 8 EN→JA.
    var latencies: [Double] = []
    var totalChars = 0
    var totalSeconds = 0.0
    let ja = BenchSentences.japanese
    let en = BenchSentences.english

    for src in ja {
        let t0 = Date()
        do {
            let out = try await engine.translate(src, .jaToEn)
            let dt = elapsed(t0)
            latencies.append(dt * 1000)
            totalChars += out.count
            totalSeconds += dt
            transcript.jaEn.append((src, out))
        } catch {
            await engine.evict()
            return (BenchResult(
                name: entry.name,
                coldLoadMS: coldLoadMS, warmReloadMS: 0,
                loadedDeltaMB: loadedDeltaMB,
                p50: 0, p95: 0, meanMS: 0, charsPerSec: 0,
                skippedReason: "ja→en translate failed: \(error)"), transcript)
        }
    }
    for src in en {
        let t0 = Date()
        do {
            let out = try await engine.translate(src, .enToJa)
            let dt = elapsed(t0)
            latencies.append(dt * 1000)
            totalChars += out.count
            totalSeconds += dt
            transcript.enJa.append((src, out))
        } catch {
            await engine.evict()
            return (BenchResult(
                name: entry.name,
                coldLoadMS: coldLoadMS, warmReloadMS: 0,
                loadedDeltaMB: loadedDeltaMB,
                p50: 0, p95: 0, meanMS: 0, charsPerSec: 0,
                skippedReason: "en→ja translate failed: \(error)"), transcript)
        }
    }

    // Evict (MLX evict() already calls Memory.clearCache())
    await engine.evict()

    // Warm reload
    let warmStart = Date()
    do {
        try await engine.load()
    } catch {
        return (BenchResult(
            name: entry.name,
            coldLoadMS: coldLoadMS, warmReloadMS: 0,
            loadedDeltaMB: loadedDeltaMB,
            p50: BenchStats.p50(latencies),
            p95: BenchStats.p95(latencies),
            meanMS: BenchStats.mean(latencies),
            charsPerSec: totalSeconds > 0 ? Double(totalChars) / totalSeconds : 0,
            skippedReason: "warm reload failed: \(error)"), transcript)
    }
    let warmReloadMS = elapsed(warmStart) * 1000

    // Evict again (cleanup)
    await engine.evict()

    let charsPerSec = totalSeconds > 0 ? Double(totalChars) / totalSeconds : 0
    return (BenchResult(
        name: entry.name,
        coldLoadMS: coldLoadMS,
        warmReloadMS: warmReloadMS,
        loadedDeltaMB: loadedDeltaMB,
        p50: BenchStats.p50(latencies),
        p95: BenchStats.p95(latencies),
        meanMS: BenchStats.mean(latencies),
        charsPerSec: charsPerSec), transcript)
}

// ── Run ─────────────────────────────────────────────────────────────────────

var results: [BenchResult] = []
var transcripts: [String: Transcript] = [:]
for entry in configs {
    let (result, transcript) = await measureConfig(entry)
    results.append(result)
    transcripts[result.name] = transcript
}

// ── Machine info ────────────────────────────────────────────────────────────

var memsize: UInt64 = 0
var len = MemoryLayout<UInt64>.size
sysctlbyname("hw.memsize", &memsize, &len, nil, 0)
let ramGB = Double(memsize) / (1024.0 * 1024.0 * 1024.0)
let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

// ── Markdown report ─────────────────────────────────────────────────────────

var report = ""
report += "# mbt-bench Report\n\n"
report += "**Machine:** Apple Silicon, RAM: \(String(format: "%.0f", ramGB)) GB, macOS \(osVersion)\n"
report += "**llama.cpp pin:** b9878 | **mlx-swift-lm:** 3.31.4\n\n"
report += "## Summary\n\n"
report += BenchFormatter.markdownTable(results)
report += "\n## Transcripts\n\n"
for r in results {
    report += "### \(r.name)\n"
    if let reason = r.skippedReason {
        report += "[skipped: \(reason)]\n\n"
        continue
    }
    let t = transcripts[r.name]
    report += "#### JA→EN\n"
    report += "| Source | Output |\n|---|---|\n"
    for (src, out) in (t?.jaEn ?? []) {
        report += "| \(src) | \(out) |\n"
    }
    report += "\n#### EN→JA\n"
    report += "| Source | Output |\n|---|---|\n"
    for (src, out) in (t?.enJa ?? []) {
        report += "| \(src) | \(out) |\n"
    }
    report += "\n"
}

FileHandle.standardOutput.write(Data(report.utf8))

if let path = outPath {
    try? report.write(toFile: path, atomically: true, encoding: .utf8)
}

// _exit, not exit: llama.cpp b9878 aborts in a ggml-metal static destructor at process
// teardown (same rationale as the mbt executable).
_exit(0)
