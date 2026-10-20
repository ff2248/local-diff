import Foundation
import Testing
@testable import DiffCore

private func diff(_ l: String, _ r: String, _ o: CompareOptions = CompareOptions()) -> DiffResult {
    computeDiff(left: l, right: r, options: o)
}

@Test func identicalHasNoHighlights() {
    let d = diff("a\nb", "a\nb")
    #expect(d.rows == [DiffRow(left: 0, right: 0, kind: .unchanged), DiffRow(left: 1, right: 1, kind: .unchanged)])
    #expect(d.leftHighlights.isEmpty && d.rightHighlights.isEmpty)
}

@Test func modifiedLineInline() {
    let d = diff("a\nbanana split\nc", "a\nbanana Split\nc")
    #expect(d.rows[1] == DiffRow(left: 1, right: 1, kind: .modified))
    #expect(d.leftHighlights.contains(Highlight(range: NSRange(location: 9, length: 5), kind: .textDeleted)))
    #expect(d.rightHighlights.contains(Highlight(range: NSRange(location: 9, length: 5), kind: .textInserted)))
}

@Test func chineseInline() {
    let d = diff("今天天氣很好", "今天天氣不好")
    #expect(d.leftHighlights.filter { $0.kind == .textDeleted }.map(\.range) == [NSRange(location: 4, length: 1)])
    #expect(d.rightHighlights.filter { $0.kind == .textInserted }.map(\.range) == [NSRange(location: 4, length: 1)])
}

@Test func smallGapsMerge() {
    let d = diff("甲乙丙丁戊己庚辛", "甲子丙寅戊己庚辛")
    #expect(d.leftHighlights.filter { $0.kind == .textDeleted }.map(\.range) == [NSRange(location: 1, length: 3)])
}

@Test func deletedLine() {
    let d = diff("a\nb", "a")
    #expect(d.rows == [DiffRow(left: 0, right: 0, kind: .unchanged), DiffRow(left: 1, right: nil, kind: .deleted)])
    #expect(d.leftHighlights == [Highlight(range: NSRange(location: 2, length: 1), kind: .lineDeleted)])
}

@Test func unrelatedLinesAreNotPaired() {
    let d = diff("alpha beta gamma", "完全不同的內容")
    #expect(d.rows.map(\.kind) == [.deleted, .inserted])
}

@Test func crlfEqualsLf() {
    let d = diff("a\r\nb", "a\nb")
    #expect(d.leftHighlights.isEmpty && d.rightHighlights.isEmpty)
    #expect(d.leftLines == [NSRange(location: 0, length: 1), NSRange(location: 3, length: 1)])
}

@Test func emojiInlineRange() {
    let d = diff("😀 hello a", "😀 hello b")
    #expect(d.leftHighlights.filter { $0.kind == .textDeleted }.map(\.range) == [NSRange(location: 9, length: 1)])
}

@Test func emptySides() {
    #expect(diff("", "").rows.isEmpty)
    #expect(diff("", "a").rows == [DiffRow(left: nil, right: 0, kind: .inserted)])
}

@Test func ignoreOptions() {
    #expect(diff("Hello", "hello", CompareOptions(ignoreCase: true)).leftHighlights.isEmpty)
    #expect(diff("Hello", "hello").rows.map(\.kind) == [.modified])
    #expect(diff("a\n\nb", "a\nb", CompareOptions(ignoreBlankLines: true)).leftHighlights.isEmpty)
    #expect(!diff("a\n\nb", "a\nb").leftHighlights.isEmpty)
    #expect(diff("a b", "ab", CompareOptions(ignoreWhitespace: true)).leftHighlights.isEmpty)
    #expect(diff("你好，世界", "你好,世界", CompareOptions(ignoreWidth: true)).leftHighlights.isEmpty)
}

@Test func reindentedBlockStillPairs() {
    let base = (0..<1000).map { "let value\($0) = compute(items[\($0)], factor: \($0 % 7))" }
    let d = diff(base.joined(separator: "\n"), base.map { "    " + $0 }.joined(separator: "\n"))
    #expect(d.rows.allSatisfy { $0.kind == .modified })
}
