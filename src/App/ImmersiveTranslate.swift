import Foundation

/// Immersive Translate Custom API + thin OpenAI chat facade for loopback clients
/// (KISS Translator, etc.). See ADR 0011.
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
        public var contentType: String
        public init(status: Int, body: Data, contentType: String = "application/json") {
            self.status = status
            self.body = body
            self.contentType = contentType
        }
    }

    /// Route a loopback request. OpenAI clients use `/v1/chat/completions` and
    /// `/v1/models`; Immersive Custom API posts JSON to `/`.
    public static func handleHTTP(
        method: String,
        path: String,
        body: Data,
        translate: @escaping (String, LanguagePair) async throws -> String
    ) async -> HTTPResult {
        await handleHTTP(method: method, path: path, body: body) { items in
            var out: [String] = []
            out.reserveCapacity(items.count)
            for item in items {
                out.append(try await translate(item.0, item.1))
            }
            return out
        }
    }

    public static func handleHTTP(
        method: String,
        path: String,
        body: Data,
        translateMany: ([(String, LanguagePair)]) async throws -> [String]
    ) async -> HTTPResult {
        let method = method.uppercased()
        let path = normalizePath(path)
        if method == "OPTIONS" {
            return HTTPResult(status: 204, body: Data())
        }
        if method == "GET", path == "/v1/models" || path == "/models" {
            return modelsResult()
        }
        guard method == "POST" else {
            return errorResult(405, "method not allowed")
        }
        if path.hasSuffix("/chat/completions") || path == "/v1/chat/completions" {
            return await handleChatPOST(body: body, translateMany: translateMany)
        }
        return await handlePOST(body: body, translateMany: translateMany)
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

    private static func handleChatPOST(
        body: Data,
        translateMany: ([(String, LanguagePair)]) async throws -> [String]
    ) async -> HTTPResult {
        let payload = HTTPPayload.unwrap(body)
        guard let obj = jsonObject(from: payload) else {
            return errorResult(400, "invalid json")
        }
        return await handleChat(obj, translateMany: translateMany)
    }

    private static func normalizePath(_ path: String) -> String {
        let trimmed = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        if trimmed.isEmpty { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }

    private static func modelsResult() -> HTTPResult {
        let payload: [String: Any] = [
            "object": "list",
            "data": [
                [
                    "id": "menubartranslate",
                    "object": "model",
                    "created": 0,
                    "owned_by": "local",
                ],
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        return HTTPResult(status: 200, body: data)
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
        let combined = system + "\n" + user
        let stream = (obj["stream"] as? Bool) ?? false
        let model = (obj["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "menubartranslate"

        let extracted = extractChatTexts(from: user, prompt: combined)
        guard let target = extracted.target ?? inferTarget(combined) else {
            return errorResult(400, "unsupported language pair: auto-?")
        }
        guard !extracted.texts.isEmpty else {
            return errorResult(400, "empty translation text")
        }

        let custom = await handleCustom(
            [
                "source_lang": "auto",
                "target_lang": target.code,
                "text_list": extracted.texts,
            ],
            translateMany: translateMany
        )
        guard custom.status == 200,
              let responseObj = jsonObject(from: custom.body),
              let rows = responseObj["translations"] as? [[String: Any]]
        else {
            return custom
        }
        let translated = rows.map { $0["text"] as? String ?? "" }
        let content: String
        switch extracted.style {
        case .kissJSON:
            var items: [[String: Any]] = []
            for (i, text) in translated.enumerated() {
                let id = extracted.ids.indices.contains(i) ? extracted.ids[i] : i
                items.append(["id": id, "text": text])
            }
            let data = (try? JSONSerialization.data(withJSONObject: items)) ?? Data("[]".utf8)
            content = String(decoding: data, as: UTF8.self)
        case .immersivePercent:
            content = translated.joined(separator: "\n\n%%\n\n")
        case .plain:
            content = translated.joined(separator: "\n")
        }

        if stream {
            return sseChatResult(model: model, content: content)
        }
        let reply: [String: Any] = [
            "id": "chatcmpl-mbt",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [
                [
                    "index": 0,
                    "message": ["role": "assistant", "content": content],
                    "finish_reason": "stop",
                ],
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
        return HTTPResult(status: 200, body: data)
    }

    private enum ChatStyle {
        case plain
        case immersivePercent
        case kissJSON
    }

    private struct ExtractedChat {
        var texts: [String]
        var ids: [Int]
        var style: ChatStyle
        var target: AppLanguage?
    }

    /// Pull translation segments out of Immersive (`%%`) or KISS (concise / JSON array) prompts.
    private static func extractChatTexts(from user: String, prompt: String) -> ExtractedChat {
        if let fromObject = extractSegmentsObject(user) {
            return ExtractedChat(
                texts: fromObject.texts, ids: fromObject.ids, style: .kissJSON,
                target: fromObject.target ?? inferTarget(prompt)
            )
        }
        if let fromArray = extractJSONSegmentArray(user) {
            return ExtractedChat(
                texts: fromArray.texts, ids: fromArray.ids, style: .kissJSON,
                target: inferTarget(prompt)
            )
        }
        var parts = user.components(separatedBy: "\n\n%%\n\n")
        if parts.count == 1 {
            parts = user.components(separatedBy: "\n%%\n")
        }
        if parts.count > 1 {
            if let first = parts.first {
                parts[0] = stripInstruction(first)
            }
            let cleaned = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return ExtractedChat(texts: cleaned, ids: [], style: .immersivePercent, target: inferTarget(prompt))
        }
        let plain = stripInstruction(user).trimmingCharacters(in: .whitespacesAndNewlines)
        return ExtractedChat(
            texts: plain.isEmpty ? [] : [plain],
            ids: [],
            style: .plain,
            target: inferTarget(prompt)
        )
    }

    private static func extractSegmentsObject(_ user: String)
        -> (texts: [String], ids: [Int], target: AppLanguage?)?
    {
        guard let obj = jsonObject(from: Data(user.utf8)) ?? trailingJSONObject(in: user) else {
            return nil
        }
        guard let segments = obj["segments"] as? [[String: Any]], !segments.isEmpty else {
            return nil
        }
        var texts: [String] = []
        var ids: [Int] = []
        for (i, seg) in segments.enumerated() {
            guard let text = seg["text"] as? String else { continue }
            texts.append(text)
            if let id = seg["id"] as? Int {
                ids.append(id)
            } else if let id = seg["id"] as? NSNumber {
                ids.append(id.intValue)
            } else {
                ids.append(i)
            }
        }
        guard !texts.isEmpty else { return nil }
        let target: AppLanguage?
        if let code = obj["targetLanguage"] as? String {
            target = language(from: code) ?? inferTarget(code)
        } else {
            target = nil
        }
        return (texts, ids, target)
    }

    private static func extractJSONSegmentArray(_ user: String) -> (texts: [String], ids: [Int])? {
        guard let arr = trailingJSONArray(in: user) as? [[String: Any]], !arr.isEmpty else {
            return nil
        }
        guard arr.contains(where: { $0["text"] != nil }) else { return nil }
        var texts: [String] = []
        var ids: [Int] = []
        for (i, seg) in arr.enumerated() {
            guard let text = seg["text"] as? String else { continue }
            texts.append(text)
            if let id = seg["id"] as? Int {
                ids.append(id)
            } else if let id = seg["id"] as? NSNumber {
                ids.append(id.intValue)
            } else {
                ids.append(i)
            }
        }
        return texts.isEmpty ? nil : (texts, ids)
    }

    private static func trailingJSONObject(in text: String) -> [String: Any]? {
        guard let start = text.lastIndex(of: "{") else { return nil }
        return jsonObject(from: Data(String(text[start...]).utf8))
    }

    private static func trailingJSONArray(in text: String) -> Any? {
        guard let start = text.lastIndex(of: "[") else { return nil }
        let slice = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return try? JSONSerialization.jsonObject(with: Data(slice.utf8))
    }

    private static func sseChatResult(model: String, content: String) -> HTTPResult {
        let created = Int(Date().timeIntervalSince1970)
        func chunk(_ delta: [String: Any], finish: String?) -> String {
            var choice: [String: Any] = ["index": 0, "delta": delta]
            if let finish { choice["finish_reason"] = finish } else { choice["finish_reason"] = NSNull() }
            let payload: [String: Any] = [
                "id": "chatcmpl-mbt",
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [choice],
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
            return "data: \(String(decoding: data, as: UTF8.self))\n\n"
        }
        var body = chunk(["role": "assistant", "content": content], finish: nil)
        body += chunk([:], finish: "stop")
        body += "data: [DONE]\n\n"
        return HTTPResult(status: 200, body: Data(body.utf8), contentType: "text/event-stream")
    }

    static func inferTarget(_ prompt: String) -> AppLanguage? {
        let lower = prompt.lowercased()
        if prompt.contains("日本語") || lower.contains("japanese") || lower.contains("\"ja\"") {
            return .ja
        }
        if prompt.contains("中文") || lower.contains("chinese") || lower.contains("zh-cn")
            || lower.contains("zh-tw") || lower.contains("\"zh\"")
        {
            return .zh
        }
        if prompt.contains("英語") || prompt.contains("英文") || lower.contains("english")
            || lower.contains("\"en\"")
        {
            return .en
        }
        // Prefer "into <lang>" / "to <lang>" phrases used by KISS concise prompts.
        if let into = matchLanguage(after: "into ", in: lower)
            ?? matchLanguage(after: "to ", in: lower)
        {
            return into
        }
        return nil
    }

    private static func matchLanguage(after marker: String, in lower: String) -> AppLanguage? {
        guard let range = lower.range(of: marker) else { return nil }
        let rest = lower[range.upperBound...]
        if rest.hasPrefix("japanese") || rest.hasPrefix("ja") { return .ja }
        if rest.hasPrefix("english") || rest.hasPrefix("en") { return .en }
        if rest.hasPrefix("chinese") || rest.hasPrefix("zh") { return .zh }
        return nil
    }

    static func stripInstruction(_ text: String) -> String {
        let markers = [
            "without any explanation:\n",
            "without any additional explanation:\n",
            "without any explanation：\n",
            "：\n\n", ":\n\n", "：\n", ":\n",
        ]
        for marker in markers {
            guard let range = text.range(of: marker, options: .caseInsensitive) else { continue }
            let head = text[text.startIndex..<range.lowerBound]
            if head.contains("翻訳") || head.localizedCaseInsensitiveContains("translate")
                || head.localizedCaseInsensitiveContains("output only")
            {
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
