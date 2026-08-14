import Foundation

/// Immersive Translate Custom API (https://immersivetranslate.com/en/docs/services/custom/).
/// Language pairs are gated by `LanguagePair.isSupported` (ja / en / zh).
public enum ImmersiveTranslate {
    public static let defaultPort: UInt16 = 18787

    public static func port(environment: [String: String] = ProcessInfo.processInfo.environment) -> UInt16 {
        if let raw = environment["MBT_HTTP_PORT"], let parsed = UInt16(raw), parsed > 0 {
            return parsed
        }
        return defaultPort
    }

    public static func language(from tag: String) -> AppLanguage? {
        if tag.caseInsensitiveCompare("auto") == .orderedSame { return nil }
        return AppLanguage(preferredTag: tag)
    }

    public struct HTTPResult: Equatable, Sendable {
        public var status: Int
        public var body: Data
        public init(status: Int, body: Data) {
            self.status = status
            self.body = body
        }
    }

    public static func handlePOST(
        body: Data,
        translate: @escaping (String, LanguagePair) async throws -> String
    ) async -> HTTPResult {
        await handlePOST(body: body) { items in
            var out: [String] = []
            out.reserveCapacity(items.count)
            for item in items {
                out.append(try await translate(item.0, item.1))
            }
            return out
        }
    }

    public static func handlePOST(
        body: Data,
        translateMany: ([(String, LanguagePair)]) async throws -> [String]
    ) async -> HTTPResult {
        let payload = HTTPPayload.unwrap(body)
        guard let obj = jsonObject(from: payload) else {
            let hex = HTTPPayload.hexPrefix(body)
            let preview = String(decoding: payload.prefix(300), as: UTF8.self)
            FileHandle.standardError.write(
                Data("immersive http invalid json hex[\(hex)] \(preview)\n".utf8)
            )
            let dump = CrashLog.logsDirectory().appendingPathComponent("last-http-body.bin")
            try? body.write(to: dump)
            return errorResult(400, "invalid json")
        }
        if obj["messages"] != nil {
            return await handleChat(obj, translateMany: translateMany)
        }
        return await handleCustom(obj, translateMany: translateMany)
    }

    private static func handleCustom(
        _ obj: [String: Any],
        translateMany: ([(String, LanguagePair)]) async throws -> [String]
    ) async -> HTTPResult {
        guard let req = Request.parse(obj) else {
            return errorResult(400, "invalid json")
        }

        guard let target = language(from: req.target_lang) else {
            return errorResult(400, "unsupported language pair: \(req.source_lang)-\(req.target_lang)")
        }

        let fixedSource = language(from: req.source_lang)
        if req.source_lang.caseInsensitiveCompare("auto") != .orderedSame, fixedSource == nil {
            return errorResult(400, "unsupported language pair: \(req.source_lang)-\(req.target_lang)")
        }

        var slots: [Translation?] = Array(repeating: nil, count: req.text_list.count)
        var jobs: [(Int, String, LanguagePair)] = []
        for (i, text) in req.text_list.enumerated() {
            let source = fixedSource ?? AppLanguage.detect(text)
            guard let source else {
                slots[i] = Translation(detected_source_lang: "auto", text: text)
                continue
            }
            if source == target {
                slots[i] = Translation(detected_source_lang: source.code, text: text)
                continue
            }
            let pair = LanguagePair.named(source: source, target: target)
            guard LanguagePair.isSupported(pair) else {
                return errorResult(400, "unsupported language pair: \(pair.token)")
            }
            jobs.append((i, text, pair))
        }
        if !jobs.isEmpty {
            do {
                let outs = try await translateMany(jobs.map { ($0.1, $0.2) })
                guard outs.count == jobs.count else {
                    return errorResult(500, "batch size mismatch")
                }
                for (j, job) in jobs.enumerated() {
                    slots[job.0] = Translation(
                        detected_source_lang: job.2.sourceCode, text: outs[j])
                }
            } catch {
                return errorResult(500, String(describing: error))
            }
        }
        let items = slots.compactMap { $0 }
        do {
            let data = try JSONEncoder().encode(Response(translations: items))
            return HTTPResult(status: 200, body: data)
        } catch {
            return errorResult(500, String(describing: error))
        }
    }

    private static func errorResult(_ status: Int, _ message: String) -> HTTPResult {
        let data = (try? JSONEncoder().encode(["error": message])) ?? Data(message.utf8)
        return HTTPResult(status: status, body: data)
    }

    private struct Request {
        var source_lang: String
        var target_lang: String
        var text_list: [String]

        static func parse(_ obj: [String: Any]) -> Request? {
            let source: String = {
                if let s = obj["source_lang"] as? String, !s.isEmpty { return s }
                return "auto"
            }()
            guard let target = obj["target_lang"] as? String, !target.isEmpty else { return nil }
            let list: [String]
            if let strings = obj["text_list"] as? [String] {
                list = strings
            } else if let mixed = obj["text_list"] as? [Any] {
                list = mixed.map { "\($0)" }
            } else if let one = obj["text_list"] as? String {
                list = [one]
            } else {
                return nil
            }
            return Request(source_lang: source, target_lang: target, text_list: list)
        }
    }

    private static func handleChat(
        _ obj: [String: Any],
        translateMany: ([(String, LanguagePair)]) async throws -> [String]
    ) async -> HTTPResult {
        let messages = obj["messages"] as? [[String: Any]] ?? []
        let system = messages.first { ($0["role"] as? String) == "system" }?["content"] as? String ?? ""
        let user = messages.last { ($0["role"] as? String) == "user" }?["content"] as? String ?? ""
        guard let target = inferTarget(system + "\n" + user) else {
            return errorResult(400, "unsupported language pair: auto-?")
        }
        var parts = user.components(separatedBy: "\n\n%%\n\n")
        if parts.count == 1 {
            parts = user.components(separatedBy: "\n%%\n")
        }
        if let first = parts.first {
            parts[0] = stripInstruction(first)
        }
        let custom = await handleCustom(
            [
                "source_lang": "auto",
                "target_lang": target.code,
                "text_list": parts,
            ],
            translateMany: translateMany
        )
        guard custom.status == 200,
              let obj = jsonObject(from: custom.body),
              let rows = obj["translations"] as? [[String: Any]]
        else {
            return custom
        }
        let translated = rows.map { $0["text"] as? String ?? "" }
        let content = translated.joined(separator: "\n\n%%\n\n")
        let reply: [String: Any] = [
            "choices": [
                ["message": ["role": "assistant", "content": content]],
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
        return HTTPResult(status: 200, body: data)
    }

    static func inferTarget(_ prompt: String) -> AppLanguage? {
        if prompt.contains("日本語") || prompt.localizedCaseInsensitiveContains("japanese") { return .ja }
        if prompt.contains("中文") || prompt.localizedCaseInsensitiveContains("chinese") { return .zh }
        if prompt.contains("英語") || prompt.localizedCaseInsensitiveContains("english") { return .en }
        return nil
    }

    static func stripInstruction(_ text: String) -> String {
        for marker in ["：\n\n", ":\n\n", "：\n", ":\n"] {
            guard let range = text.range(of: marker) else { continue }
            let head = text[text.startIndex..<range.lowerBound]
            if head.contains("翻訳") || head.localizedCaseInsensitiveContains("translate") {
                return String(text[range.upperBound...])
            }
        }
        return text
    }

    static func jsonObject(from data: Data) -> [String: Any]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        let s = String(decoding: data, as: UTF8.self)
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        for i in s[start...].indices {
            let c = s[i]
            if inString {
                if escape {
                    escape = false
                    continue
                }
                if c == "\\" { escape = true; continue }
                if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true; continue }
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 {
                    let slice = String(s[start...i])
                    return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
                }
            }
        }
        return nil
    }

    private struct Response: Encodable {
        var translations: [Translation]
    }

    private struct Translation: Encodable {
        var detected_source_lang: String
        var text: String
    }
}

/// UserDefaults flag for the loopback HTTP listener. Unset means off.
public enum LoopbackPreference {
    public static let key = "httpLoopbackEnabled"

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    public static func setEnabled(_ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key)
    }
}
