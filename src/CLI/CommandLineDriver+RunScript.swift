import Foundation

/// `mbt run-script <file>` — replays a deterministic event script over a `ManualClock` and a
/// `FakePressureSource`, printing the residency trace after each step. This is the most
/// direct way to *feed input and observe the state transitions* the ADRs describe (floor,
/// warn-debounce, idle-timeout, critical-immediate) live from the shell.
///
/// Script grammar (one command per line; `#` and blank lines ignored):
///   translate <ja-en|en-ja> <text...>
///   pressure  <normal|warn|critical>
///   advance   <seconds>
///   tick
extension CommandLineDriver {
    func runScript(_ args: [String], out: TextSink, err: TextSink) async -> Int32 {
        guard let path = args.first else {
            err.write("usage: mbt run-script <file>\n")
            return 1
        }
        let source: String
        do {
            source = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            err.write("cannot read script '\(path)': \(error)\n")
            return 1
        }

        let clock = ManualClock()
        let pressure = FakePressureSource()
        let manager = ResidencyManager(
            config: .eightGigabyteDefault, clock: clock, pressureSource: pressure)
        let engine = FakeEngine()

        var trace: [ResidencyEvent] = []
        var evictionPending = false
        manager.onEvent = { trace.append($0) }
        manager.onEvict = { evictionPending = true }

        func drain() async {
            while evictionPending {
                evictionPending = false
                await engine.evict()
                manager.completeEviction()
            }
        }

        func report(_ label: String) {
            let line = trace.isEmpty
                ? "(no transition, state=\(CommandLineDriver.stateName(manager.state)))"
                : trace.map { CommandLineDriver.stateName($0.state) }.joined(separator: "→")
            out.write("\(label)  \(line)\n")
            trace.removeAll(keepingCapacity: true)
        }

        var lineNo = 0
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNo += 1
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let tokens = line.split(separator: " ").map(String.init)

            switch tokens[0] {
            case "translate":
                guard tokens.count >= 3, let dir = try? Direction.parse(tokens[1]) else {
                    err.write("line \(lineNo): usage: translate <ja-en|en-ja> <text>\n")
                    return 1
                }
                let text = tokens[2...].joined(separator: " ")
                do {
                    if manager.needsLoad {
                        try manager.beginLoad()
                        try await engine.load()
                        try manager.completeLoad()
                    }
                    try manager.beginInference()
                    let result = try await engine.translate(text, dir.pair)
                    try manager.endInference()
                    await drain()
                    out.write("= \(result)\n")
                    report("translate:")
                } catch {
                    err.write("line \(lineNo): translation failed: \(error)\n")
                    return 2
                }

            case "pressure":
                guard tokens.count == 2, let level = CommandLineDriver.pressureLevel(tokens[1]) else {
                    err.write("line \(lineNo): usage: pressure <normal|warn|critical>\n")
                    return 1
                }
                pressure.emit(level)
                await drain()
                report("pressure \(tokens[1]):")

            case "advance":
                guard tokens.count == 2, let seconds = Double(tokens[1]) else {
                    err.write("line \(lineNo): usage: advance <seconds>\n")
                    return 1
                }
                clock.advance(by: .seconds(seconds))
                manager.tick()
                await drain()
                report("advance \(tokens[1])s:")

            case "tick":
                manager.tick()
                await drain()
                report("tick:")

            default:
                err.write("line \(lineNo): unknown command '\(tokens[0])'\n")
                return 1
            }
        }
        return 0
    }
}
