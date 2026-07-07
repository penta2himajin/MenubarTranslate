import Testing
@testable import MenubarTranslateCore

@Suite("PromptBuilder")
struct PromptBuilderTests {
    /// Regression: the gemma turn header must terminate with a newline
    /// (`<start_of_turn>model\n`). Omitting it caused EN→JA artifacts on
    /// GGUF Q4_K_M (instruction-like prefixes, wrong-language output).
    @Test func gemmaPromptEndsModelTurnWithNewline() {
        let p = PromptBuilder.gemma(
            text: "hello",
            pair: LanguagePair(sourceCode: "en", sourceName: "English",
                               targetCode: "ja", targetName: "Japanese"))
        #expect(p.hasSuffix("<start_of_turn>model\n"))
    }
}
