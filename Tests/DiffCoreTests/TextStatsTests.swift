import Testing
@testable import DiffCore

@Test func countsMixedText() {
    let s = TextStats(text: "你好，world\n第二行")
    #expect(s == TextStats(characters: 11, cjkCharacters: 5, lines: 2, estimatedTokens: 7))
}

@Test func lineCounting() {
    #expect(TextStats(text: "").lines == 0)
    #expect(TextStats(text: "a\n").lines == 1)
    #expect(TextStats(text: "\n").lines == 1)
    #expect(TextStats(text: "a\nb\n").lines == 2)
    #expect(TextStats(text: "a\r\nb").lines == 2)
    #expect(TextStats(text: "a\r\nb").characters == 2)
}

@Test func emojiIsOneCharacter() {
    #expect(TextStats(text: "😀").characters == 1)
}
