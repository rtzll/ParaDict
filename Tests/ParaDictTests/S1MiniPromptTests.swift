import Testing

@testable import ParaDict

struct S1MiniPromptTests {
  @Test func rendersTheDocumentedModelContractExactly() {
    #expect(
      S1MiniPrompt.systemMessage
        == "You are a text normalizer for speech-to-text transcripts. The input begins "
        + "with a control line specifying the styling, structure, and context settings; "
        + "clean the transcript to match those settings and output only the cleaned text."
    )
    #expect(
      S1MiniPrompt.userMessage(for: "so um send the report by uh friday")
        == "[Styling: semi-formal] [Structure: prose] [Context: general]\n"
        + "so um send the report by uh friday"
    )
    #expect(S1MiniPrompt.additionalContext.enableThinking == false)
  }
}
