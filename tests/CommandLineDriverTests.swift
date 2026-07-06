import Testing
import Foundation
@testable import MenubarTranslateCore

@Suite("CommandLineDriver — mbt surface")
struct CommandLineDriverTests {
    private func run(_ args: [String], stdin: String? = nil) async -> (code: Int32, out: String, err: String) {
        let out = StringSink()
        let err = StringSink()
        let code = await CommandLineDriver().run(args, stdin: stdin, out: out, err: err)
        return (code, out.buffer, err.buffer)
    }

    @Test("positional text translates and exits 0")
    func positionalText() async {
        let r = await run(["--dir", "ja-en", "こんにちは"])
        #expect(r.code == 0)
        #expect(r.out == "[ja-en] こんにちは\n")
    }

    @Test("reads stdin when no positional text is given")
    func stdinPath() async {
        let r = await run(["--dir", "en-ja"], stdin: "hello\n")
        #expect(r.code == 0)
        #expect(r.out == "[en-ja] hello\n")
    }

    @Test("missing --dir is a usage error (exit 1)")
    func missingDirection() async {
        let r = await run(["hello"])
        #expect(r.code == 1)
    }

    @Test("unknown direction is a usage error (exit 1)")
    func badDirection() async {
        let r = await run(["--dir", "fr-en", "hi"])
        #expect(r.code == 1)
    }

    @Test("a native engine is unavailable in this build (exit 3)")
    func engineUnavailable() async {
        let r = await run(["--dir", "ja-en", "--engine", "llama", "hi"])
        #expect(r.code == 3)
    }

    @Test("no input at all is a usage error (exit 1)")
    func noInput() async {
        let r = await run(["--dir", "ja-en"], stdin: nil)
        #expect(r.code == 1)
    }

    @Test("verbose prints the lifecycle trace to stderr")
    func verboseTrace() async {
        let r = await run(["--dir", "ja-en", "-v", "hi"])
        #expect(r.code == 0)
        #expect(r.err.contains("Unloaded→Loading→Ready→Inferring→Ready"))
    }

    @Test("json emits a structured result on stdout")
    func jsonOutput() async {
        let r = await run(["--dir", "ja-en", "--json", "hi"])
        #expect(r.code == 0)
        #expect(r.out.contains("\"text\":\"[ja-en] hi\""))
    }

    @Test("simulated critical pressure evicts after use")
    func simulateCritical() async {
        let r = await run(["--dir", "ja-en", "-v", "--simulate-pressure", "critical", "hi"])
        #expect(r.code == 0)
        #expect(r.err.contains("Evicting→Unloaded"))
    }

    @Test("run-script replays events and shows floor/debounce/idle/critical behavior")
    func runScript() async throws {
        let script = """
        # deterministic residency demo
        translate ja-en こんにちは
        pressure warn
        advance 10
        """
        let path = NSTemporaryDirectory() + "mbt-\(UUID().uuidString).mbt"
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let r = await run(["run-script", path])
        #expect(r.code == 0)
        #expect(r.out.contains("= [ja-en] こんにちは"))
        // warn persisted past debounce (2 s) and floor (5 s) → eviction on the advance tick.
        #expect(r.out.contains("Evicting→Unloaded"))
    }
}
