import Foundation
import Testing
@testable import MenubarTranslateCore

@Suite("Immersive Translate API")
struct ImmersiveTranslateTests {

    @Test("port defaults to 18787 and honours MBT_HTTP_PORT")
    func portFromEnv() {
        #expect(ImmersiveTranslate.port(environment: [:]) == 18787)
        #expect(ImmersiveTranslate.port(environment: ["MBT_HTTP_PORT": "19001"]) == 19001)
        #expect(ImmersiveTranslate.port(environment: ["MBT_HTTP_PORT": "nope"]) == 18787)
    }

    @Test("loopback preference is off until enabled")
    func loopbackPreferenceDefaultsOff() {
        let suite = "mbt.tests.loopback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(LoopbackPreference.isEnabled(defaults) == false)
        LoopbackPreference.setEnabled(true, defaults: defaults)
        #expect(LoopbackPreference.isEnabled(defaults) == true)
        LoopbackPreference.setEnabled(false, defaults: defaults)
        #expect(LoopbackPreference.isEnabled(defaults) == false)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("maps Immersive language tags onto the ja/en/zh pool")
    func mapsTags() {
        #expect(ImmersiveTranslate.language(from: "ja") == .ja)
        #expect(ImmersiveTranslate.language(from: "en-US") == .en)
        #expect(ImmersiveTranslate.language(from: "zh-CN") == .zh)
        #expect(ImmersiveTranslate.language(from: "zh-TW") == .zh)
        #expect(ImmersiveTranslate.language(from: "fr") == nil)
        #expect(ImmersiveTranslate.language(from: "auto") == nil)
    }

    @Test("POST translates a supported pair via the injected engine")
    func postSupportedPair() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "source_lang": "ja",
            "target_lang": "en",
            "text_list": ["こんにちは", "世界"],
        ])
        let result = await ImmersiveTranslate.handlePOST(body: body) { text, pair in
            "[\(pair.token)] \(text)"
        }
        #expect(result.status == 200)
        let json = try JSONSerialization.jsonObject(with: result.body) as? [String: Any]
        let translations = json?["translations"] as? [[String: String]]
        #expect(translations == [
            ["detected_source_lang": "ja", "text": "[ja-en] こんにちは"],
            ["detected_source_lang": "ja", "text": "[ja-en] 世界"],
        ])
    }

    @Test("POST accepts OpenAI chat completions used by Immersive AI")
    func postOpenAIChat() async throws {
        let body = Data(
            """
            {"model":"","messages":[{"role":"system","content":"流暢な日本語に翻訳"},{"role":"user","content":"日本語に翻訳してください：\\n\\nDownloads\\n\\n%%\\n\\nSupport"}]} trailing
            """.utf8
        )
        let result = await ImmersiveTranslate.handlePOST(body: body) { text, pair in
            "[\(pair.token)] \(text)"
        }
        #expect(result.status == 200)
        let json = try JSONSerialization.jsonObject(with: result.body) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: String]
        #expect(message?["content"] == "[en-ja] Downloads\n\n%%\n\n[en-ja] Support")
    }

    @Test("POST accepts a string text_list and omitted source_lang")
    func postStringTextListAndAutoSource() async throws {
        let body = Data("""
        {"target_lang":"en","text_list":"こんにちは"}
        """.utf8)
        let result = await ImmersiveTranslate.handlePOST(body: body) { text, pair in
            "[\(pair.token)] \(text)"
        }
        #expect(result.status == 200)
        let json = try JSONSerialization.jsonObject(with: result.body) as? [String: Any]
        let translations = json?["translations"] as? [[String: String]]
        #expect(translations == [
            ["detected_source_lang": "ja", "text": "[ja-en] こんにちは"],
        ])
    }

    @Test("HTTP parser waits for a body without Content-Length until the stream ends")
    func httpParseWithoutContentLength() {
        let raw = Data("POST / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n{\"target_lang\":\"en\",\"text_list\":[\"hi\"]}".utf8)
        #expect(HTTPRequest.parse(raw, complete: false) == nil)
        let parsed = HTTPRequest.parse(raw, complete: true)
        #expect(parsed?.method == "POST")
        #expect(String(data: parsed?.body ?? Data(), encoding: .utf8) == "{\"target_lang\":\"en\",\"text_list\":[\"hi\"]}")
    }

    @Test("POST accepts gzip-compressed JSON")
    func postGzipJSON() async throws {
        let gz = Data([
            31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 171, 86, 42, 73, 44, 74, 79, 45, 137, 207, 73, 204,
            75, 87, 178, 82, 80, 74, 205, 83, 210, 81, 80, 42, 73, 173, 0, 10, 101, 22, 151, 0, 133,
            162, 149, 50, 50, 149, 98, 107, 1, 85, 174, 109, 45, 42, 0, 0, 0,
        ] as [UInt8])
        #expect(HTTPPayload.isGzip(gz))
        let result = await ImmersiveTranslate.handlePOST(body: gz) { text, pair in
            "[\(pair.token)] \(text)"
        }
        #expect(result.status == 200)
    }

    @Test("HTTP parser decodes chunked Transfer-Encoding")
    func httpParseChunked() {
        let json = "{\"target_lang\":\"en\",\"text_list\":[\"hi\"]}"
        let chunk = String(json.utf8.count, radix: 16) + "\r\n" + json + "\r\n0\r\n\r\n"
        let raw = Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n\(chunk)".utf8)
        let parsed = HTTPRequest.parse(raw, complete: true)
        #expect(String(data: parsed?.body ?? Data(), encoding: .utf8) == json)
    }

    @Test("POST rejects pairs outside LanguagePair.isSupported")
    func postRejectsUnsupported() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "source_lang": "fr",
            "target_lang": "en",
            "text_list": ["bonjour"],
        ])
        let result = await ImmersiveTranslate.handlePOST(body: body) { _, _ in
            Issue.record("engine must not run for an unsupported pair")
            return ""
        }
        #expect(result.status == 400)
        let text = String(data: result.body, encoding: .utf8) ?? ""
        #expect(text.contains("unsupported language pair"))
    }

    @Test("same-language items are echoed without calling the engine")
    func echoesSameLanguage() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "source_lang": "en",
            "target_lang": "en",
            "text_list": ["hello"],
        ])
        var called = false
        let result = await ImmersiveTranslate.handlePOST(body: body) { _, _ in
            called = true
            return "nope"
        }
        #expect(!called)
        #expect(result.status == 200)
        let json = try JSONSerialization.jsonObject(with: result.body) as? [String: Any]
        let translations = json?["translations"] as? [[String: String]]
        #expect(translations == [["detected_source_lang": "en", "text": "hello"]])
    }

    @Test("auto source uses script detection then isSupported")
    func autoSourceDetects() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "source_lang": "auto",
            "target_lang": "en",
            "text_list": ["こんにちは"],
        ])
        let result = await ImmersiveTranslate.handlePOST(body: body) { text, pair in
            #expect(pair.token == "ja-en")
            return "[\(pair.token)] \(text)"
        }
        #expect(result.status == 200)
        let json = try JSONSerialization.jsonObject(with: result.body) as? [String: Any]
        let translations = json?["translations"] as? [[String: String]]
        #expect(translations?.first?["detected_source_lang"] == "ja")
        #expect(translations?.first?["text"] == "[ja-en] こんにちは")
    }
}
