import Foundation
import Testing
@testable import DiffCore

@Test func normalizedKeyAllOptions() {
    let all = CompareOptions(ignoreWhitespace: true, ignoreBlankLines: true, ignoreCase: true, ignoreWidth: true)
    #expect(normalizedKey("A，B　c", all) == "a,bc")
    #expect(normalizedKey("A，B　c", CompareOptions()) == "A，B　c")
}

@Test func tokenKeys() {
    #expect(tokenize("ab12 你好😀", CompareOptions()).map(\.key) == ["ab12", " ", "你", "好", "😀"])
    #expect(tokenize("ab12 你好😀", CompareOptions(ignoreWhitespace: true)).map(\.key) == ["ab12", "你", "好", "😀"])
    #expect(tokenize("AbC", CompareOptions(ignoreCase: true)).map(\.key) == ["abc"])
}

@Test func tokenRangesAreUTF16() {
    let tokens = tokenize("ab12 你好😀", CompareOptions())
    #expect(tokens.map(\.range) == [NSRange(location: 0, length: 4), NSRange(location: 4, length: 1),
                                    NSRange(location: 5, length: 1), NSRange(location: 6, length: 1),
                                    NSRange(location: 7, length: 2)])
}
