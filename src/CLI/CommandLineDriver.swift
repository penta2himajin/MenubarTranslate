import ArgumentParser
import Foundation

/// The `mbt` console wrapper's logic, kept in the library (not the executable target) so the
/// whole CLI surface is unit-testable. `mbt/main.swift` is a thin forwarder.
///
/// Exit codes: 0 success · 1 usage/parse error · 2 translation/engine error · 3 unavailable
/// (e.g. a native engine not built into this configuration).
public struct CommandLineDriver {
    public init() {}

    /// Parsed options for the default (translate) mode.
    struct Options: ParsableArguments {
        @Option(name: [.short, .customLong("dir")], help: "Translation direction: ja-en | en-ja")
        var direction: String

        @Option(name: .customLong("engine"), help: "Engine: fake | llama | mlx (default: fake)")
        var engine: String = "fake"

        @ArgumentParser.Flag(name: [.short, .long], help: "Print the lifecycle+pressure trace to stderr")
        var verbose = false

        @ArgumentParser.Flag(name: .long, help: "Emit result and trace as JSON on stdout")
        var json = false

        @Option(name: .long, help: "Idle-timeout override, seconds")
        var idleTimeout: Double?

        @Option(name: .long, help: "Residency-floor override, seconds")
        var residencyFloor: Double?

        @Option(name: .long, help: "Warn-debounce override, seconds")
        var warnDebounce: Double?

        @Option(name: .long, help: "Start under simulated pressure: normal | warn | critical")
        var simulatePressure: String?

        @Argument(help: "Text to translate; if omitted, read from stdin")
        var text: [String] = []
    }

    /// Run the CLI. `stdin` is the already-read piped text (or nil). Output goes to the
    /// injected sinks. Returns the process exit code.
    public func run(_ args: [String], stdin: String?, out: TextSink, err: TextSink) async -> Int32 {
        if args.first == "run-script" {
            return await runScript(Array(args.dropFirst()), out: out, err: err)
        }

        let options: Options
        do {
            options = try Options.parse(args)
        } catch {
            err.write(Options.message(for: error) + "\n")
            return 1
        }

        // Direction.
        let direction: Direction
        do {
            direction = try Direction.parse(options.direction)
        } catch {
            err.write("\(error)\n")
            return 1
        }

        // Engine — only the fake engine is linked in this milestone.
        guard options.engine == "fake" else {
            err.write("engine '\(options.engine)' is not available in this build "
                + "(only 'fake' is built in Milestone 1)\n")
            return 3
        }

        // Simulated starting pressure.
        var startPressure: PressureLevel = .normal
        if let raw = options.simulatePressure {
            guard let level = Self.pressureLevel(raw) else {
                err.write("unknown pressure '\(raw)'; expected normal | warn | critical\n")
                return 1
            }
            startPressure = level
        }

        // Input text: positional args, else stdin.
        let joined = options.text.joined(separator: " ")
        let input = joined.isEmpty ? (stdin?.trimmingCharacters(in: .newlines) ?? "") : joined
        guard !input.isEmpty else {
            err.write("no input text (pass a positional argument or pipe via stdin)\n")
            return 1
        }

        // Build the stack and translate.
        let clock = SystemClock()
        let pressure = FakePressureSource(initial: startPressure)
        let manager = ResidencyManager(config: makeConfig(options), clock: clock, pressureSource: pressure)
        let service = TranslationService(engine: FakeEngine(), residency: manager)

        do {
            let outcome = try await service.translate(input, direction)
            if options.json {
                out.write(Self.json(outcome) + "\n")
            } else {
                out.write(outcome.text + "\n")
            }
            if options.verbose {
                err.write(Self.traceLine(outcome.trace) + "\n")
            }
            return 0
        } catch {
            err.write("translation failed: \(error)\n")
            return 2
        }
    }

    private func makeConfig(_ options: Options) -> ResidencyConfig {
        var config = ResidencyConfig.eightGigabyteDefault
        if let idleTimeout = options.idleTimeout { config.idleTimeout = .seconds(idleTimeout) }
        if let residencyFloor = options.residencyFloor { config.residencyFloor = .seconds(residencyFloor) }
        if let warnDebounce = options.warnDebounce { config.warnDebounce = .seconds(warnDebounce) }
        return config
    }

    // MARK: - Formatting

    static func pressureLevel(_ raw: String) -> PressureLevel? {
        switch raw {
        case "normal": return .normal
        case "warn": return .warn
        case "critical": return .critical
        default: return nil
        }
    }

    static func stateName(_ state: WeightState) -> String {
        switch state {
        case .unloaded: return "Unloaded"
        case .loading: return "Loading"
        case .ready: return "Ready"
        case .inferring: return "Inferring"
        case .evicting: return "Evicting"
        }
    }

    /// A human-readable transition chain, e.g. `Unloaded→Loading→Ready→Inferring→Ready`.
    static func traceLine(_ trace: [ResidencyEvent]) -> String {
        ([stateName(.unloaded)] + trace.map { stateName($0.state) }).joined(separator: "→")
    }

    static func json(_ outcome: TranslationOutcome) -> String {
        let steps = outcome.trace.map { event in
            "{\"event\":\"\(event.event)\",\"state\":\"\(stateName(event.state))\","
                + "\"pressure\":\"\(event.pressure)\",\"reason\":\"\(event.reason)\"}"
        }.joined(separator: ",")
        return "{\"text\":\"\(escape(outcome.text))\",\"trace\":[\(steps)]}"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
