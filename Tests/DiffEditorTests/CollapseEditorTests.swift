import AppKit
import DiffCore
import Testing
@testable import DiffEditor

// 30 行，只有第 16 行（索引 15）不同。摺疊後隱藏索引 0..<12 與 19..<30。
private let leftLines = (0..<30).map { "第 \($0) 行的內容" }
private let rightLines = leftLines.enumerated().map { $0 == 15 ? "第 15 行改過了" : $1 }
private let leftText = leftLines.joined(separator: "\n")
private let rightText = rightLines.joined(separator: "\n")

@MainActor
private func collapsedFixture() -> (EditorFixture, DiffResult) {
    let f = EditorFixture()
    f.coordinator.setCollapseUnchanged(true)
    let result = f.load(leftText, rightText)
    return (f, result)
}

@MainActor
@Suite(.serialized)
struct CollapseEditorTests {
    @Test func collapsedByDefaultIsOff() {
        let f = EditorFixture()
        f.load(leftText, rightText)
        #expect(f.left.folds.isEmpty && f.right.folds.isEmpty)
    }

    @Test func hidesUnchangedLinesBeyondContext() {
        let (f, result) = collapsedFixture()
        #expect(f.left.folds.map(\.lineCount) == [12, 11])
        #expect(f.right.folds.map(\.lineCount) == [12, 11])
        let tops = result.leftLines.map { f.top(f.left, $0) }
        #expect(Set(tops[1..<12]).count == 1)
        #expect(tops[12] - tops[0] == Theme.lineHeight)
        #expect(f.misalignedRows(result) == 0)
    }

    @Test func markerSitsBetweenVisibleLines() {
        // 第 1 行與第 17 行改過，中間的摺疊區不是從第 0 行開始
        let lines = (0..<20).map { "line \($0) text" }
        let changed = lines.enumerated().map { [1, 17].contains($0) ? "changed \($0)" : $1 }
        let f = EditorFixture()
        f.coordinator.setCollapseUnchanged(true)
        let result = f.load(lines.joined(separator: "\n"), changed.joined(separator: "\n"))
        for view in [f.left, f.right] {
            let fold = try! #require(view.folds.first)
            let marker = try! #require(view.foldMarkerRects().first?.rect)
            let lineNumbers = view === f.left ? result.leftLines : result.rightLines
            let before = lineNumbers.lastIndex { $0.location < fold.hidden.location }!
            #expect(f.top(view, lineNumbers[before]) + Theme.lineHeight == marker.minY)
            #expect(marker.maxY == f.top(view, lineNumbers[before + fold.lineCount + 1]))
        }
    }

    @Test func unevenBlankLinesStayAligned() {
        let f = EditorFixture()
        f.coordinator.setCollapseUnchanged(true)
        let result = f.load("\n" + leftText, rightText, options: CompareOptions(ignoreWhitespace: true, ignoreBlankLines: true))
        #expect(!f.left.folds.isEmpty)
        #expect(f.misalignedRows(result) == 0)
    }

    @Test func trailingFoldStaysAlignedWhenContextWraps() {
        // 摺疊區一路到文件結尾，而前一行在左右換行數不同（忽略空白時只差在空白）
        let body = (0..<20).map { "unchanged line \($0)" }
        let left = (["changed left", "a", "b", String(repeating: "word ", count: 60)] + body).joined(separator: "\n")
        let right = (["changed right", "a", "b", String(repeating: "word  ", count: 60)] + body).joined(separator: "\n")
        let f = EditorFixture()
        f.coordinator.setCollapseUnchanged(true)
        let result = f.load(left, right, options: CompareOptions(ignoreWhitespace: true))
        #expect(!f.left.folds.isEmpty)
        #expect(f.misalignedRows(result) == 0)
        #expect(f.left.frame.height == f.right.frame.height)
    }

    @Test func trailingFoldStaysAlignedWithIgnoredBlankLine() {
        // 結尾摺疊區前面的脈絡行被補白時，部分重排不能把摺疊區切成兩列
        let long = "row word " + String(repeating: "word ", count: 40)
        let head = (0..<13).map { "row \($0) word" } + [long]
        let tail = (16..<21).map { "row \($0) word" }
        let f = EditorFixture()
        f.coordinator.setCollapseUnchanged(true)
        let result = f.load((head + [long, ""] + tail).joined(separator: "\n"), (head + ["edited 14", ""] + tail).joined(separator: "\n"),
                            options: CompareOptions(ignoreBlankLines: true))
        #expect(f.misalignedRows(result) == 0)
        #expect(f.left.foldMarkerRects().last?.rect.minY == f.right.foldMarkerRects().last?.rect.minY)
    }

    @Test(arguments: [
        ["new right", "added", "c1", "c2", "c3", "", ""],
        ["new right", "c1", "c2", "c3", "", ""],
        ["new right", "c1", "c2", "", "c3", ""],
    ])
    func paddedFoldAfterPaddedLineStaysAligned(rightHead: [String]) {
        // 摺疊區需要補白、前面也有行被補白時，連續重排會讓摺疊列從摺疊區中間排起
        let fold = (1...6).map { "f\($0)" }
        let tail = ["c4", "c5", "c6"]
        let f = EditorFixture()
        f.coordinator.setCollapseUnchanged(true)
        let result = f.load((["old left", "c1", "c2", "c3"] + fold + tail + ["end left"]).joined(separator: "\n"),
                            (rightHead + fold + tail + ["end right"]).joined(separator: "\n"),
                            options: CompareOptions(ignoreBlankLines: true))
        #expect(!f.left.folds.isEmpty)
        #expect(f.misalignedRows(result) == 0)
    }

    @Test func textIsUntouchedWhileCollapsed() {
        let (f, _) = collapsedFixture()
        #expect(f.left.string == leftText)
        f.window.makeFirstResponder(f.left)
        f.left.selectAll(nil)
        f.left.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == leftText)
        #expect(f.left.folds.count == 2)
    }

    @Test func lineNumbersSkipHiddenLines() {
        let (f, _) = collapsedFixture()
        let numbers = f.left.lineNumberPositions(in: f.left.bounds).map(\.number)
        #expect(numbers == [13, 14, 15, 16, 17, 18, 19])
    }

    @Test func visibleMarkersMatchTheirRect() {
        let (f, _) = collapsedFixture()
        let all = f.left.foldMarkerRects()
        #expect(f.left.foldMarkerRects(in: f.left.bounds).map(\.fold) == all.map(\.fold))
        let area = all[1].rect.insetBy(dx: 0, dy: 2)
        #expect(f.left.foldMarkerRects(in: area).filter { $0.rect.intersects(area) }.map(\.fold) == [all[1].fold])
    }

    @Test func clickingMarkerExpandsOnlyThatRegion() {
        let (f, _) = collapsedFixture()
        let marker = try! #require(f.left.foldMarkerRects().first?.rect)
        #expect(f.left.fold(at: NSPoint(x: marker.midX, y: marker.midY)) == f.left.folds.first)
        f.coordinator.reveal(f.left.folds[0])
        #expect(f.left.folds.map(\.lineCount) == [11])
        #expect(f.right.folds.map(\.lineCount) == [11])
    }

    @Test func caretEnteringFoldExpandsIt() {
        let (f, result) = collapsedFixture()
        f.window.makeFirstResponder(f.left)
        f.left.setSelectedRange(NSRange(location: result.leftLines[25].location, length: 0))
        #expect(f.left.folds.map(\.lineCount) == [12])
        #expect(f.right.folds.map(\.lineCount) == [12])
    }

    @Test func caretAtEndOfCollapsedTailExpandsIt() {
        let (f, _) = collapsedFixture()
        f.window.makeFirstResponder(f.left)
        f.left.setSelectedRange(NSRange(location: (leftText as NSString).length, length: 0))
        #expect(f.left.folds.map(\.lineCount) == [12])
    }

    @Test func pastedDocumentCollapsesItsTail() {
        // 貼上整份文件後游標停在文件結尾，結尾那段仍要摺起來
        let f = EditorFixture()
        f.coordinator.setCollapseUnchanged(true)
        f.window.makeFirstResponder(f.left)
        f.coordinator.replace(f.left, with: leftText)
        f.left.setSelectedRange(NSRange(location: (leftText as NSString).length, length: 0))
        f.load(leftText, rightText)
        #expect(f.left.folds.map(\.lineCount) == [12, 11])
    }

    @Test func typingAtEndOfDocumentExpandsCollapsedTail() async {
        let (f, _) = collapsedFixture()
        let storage = f.left.textStorage!
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "加字")
        await f.settle()
        #expect(f.left.folds.map(\.lineCount) == [12])
    }

    @Test func collapsingAroundCaretLeavesItsBlockOpen() {
        let f = EditorFixture()
        let result = f.load(leftText, rightText)
        f.window.makeFirstResponder(f.left)
        f.left.setSelectedRange(NSRange(location: result.leftLines[25].location, length: 0))
        f.coordinator.setCollapseUnchanged(true)
        #expect(f.left.folds.map(\.lineCount) == [12])
        #expect(f.right.folds.map(\.lineCount) == [12])
    }

    @Test func typingOutsideFoldKeepsItHidden() {
        let (f, result) = collapsedFixture()
        f.window.makeFirstResponder(f.left)
        f.left.setSelectedRange(NSRange(location: NSMaxRange(result.leftLines[14]), length: 0))
        f.left.insertText("加字", replacementRange: f.left.selectedRange())
        let tail = try! #require(f.left.folds.last)
        #expect((f.left.string as NSString).substring(with: tail.hidden) == leftLines[19...].joined(separator: "\n"))
    }

    @Test func replacingAllTextCollapsesAgain() async {
        let (f, _) = collapsedFixture()
        f.load(rightText, leftText)
        await f.settle()
        f.load(rightText, leftText)
        #expect(f.left.folds.map(\.lineCount) == [12, 11])
        #expect(f.right.folds.map(\.lineCount) == [12, 11])
    }

    @Test func manyFoldsStayResponsive() {
        let lines = (0..<6_000).map { "line \($0) text" }
        let changed = lines.enumerated().map { $0 % 10 == 0 ? "changed \($0)" : $1 }
        let f = EditorFixture()
        let clock = ContinuousClock()
        // 和不摺疊時載入同一份文件比，避免受機器快慢影響。查找摺疊區退回線性搜尋時約 32 倍，現在約 0.8 倍。
        let load = clock.measure { f.load(lines.joined(separator: "\n"), changed.joined(separator: "\n")) }
        let enable = clock.measure { f.coordinator.setCollapseUnchanged(true) }
        #expect(f.left.folds.count == 600)
        let reveal = clock.measure { f.coordinator.reveal(f.left.folds[300]) }
        #expect(enable < load * 4)
        #expect(reveal < load * 4)
    }

    @Test func droppedFileForgetsExpandedBlocks() throws {
        let (f, _) = collapsedFixture()
        f.coordinator.reveal(f.left.folds[0])
        let dropped = leftLines.enumerated().map { $0 == 20 ? "別處改過" : $1 }.joined(separator: "\n")
        try f.right.loadDroppedFiles([temporaryFile(Array(dropped.utf8))])
        f.load(leftText, dropped)
        #expect(f.left.folds.map(\.lineCount) == [17, 6])
    }

    @Test func turningOffShowsEverything() {
        let (f, result) = collapsedFixture()
        f.coordinator.setCollapseUnchanged(false)
        #expect(f.left.folds.isEmpty && f.right.folds.isEmpty)
        let tops = result.leftLines.map { f.top(f.left, $0) }
        #expect(zip(tops, tops.dropFirst()).allSatisfy { $1 - $0 == Theme.lineHeight })
    }
}
