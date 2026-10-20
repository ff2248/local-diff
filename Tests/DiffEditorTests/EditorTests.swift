import AppKit
import DiffCore
import Testing
@testable import DiffEditor

private let longLine = String(repeating: "這一行很長，會在窄的視窗裡自動換成好幾行。", count: 8)

@MainActor
@Suite(.serialized)
struct EditorTests {
    @Test func pairedRowsAlignAcrossWidths() async {
        let f = EditorFixture()
        let result = f.load("開頭\n\(longLine)\n中間\n結尾", "開頭\n新增的一行\n\(longLine)改\n中間\n另一行新增\n結尾")
        #expect(f.misalignedRows(result) == 0)
        await f.resize(width: 600)
        #expect(f.misalignedRows(result) == 0)
        #expect(f.left.frame.height == f.right.frame.height)
    }

    @Test func insertedFirstLineKeepsAlignment() {
        let f = EditorFixture()
        let result = f.load("共同的第一段落內容在這裡\n第二段", "新增的標題行\n共同的第一段落內容在這裡\n第二段")
        #expect(f.misalignedRows(result) == 0)
    }

    @Test func clearThenRedrawDoesNotCrash() {
        let f = EditorFixture()
        f.load("a\n" + String(repeating: "x", count: 300) + "\nzzz", "a\n新增的一行\n" + String(repeating: "x", count: 300) + "\nzzz")
        f.coordinator.replace(f.left, with: "")
        f.coordinator.replace(f.right, with: "")
        f.draw()
    }

    @Test func selectAllDeleteThenRedrawDoesNotCrash() {
        let f = EditorFixture()
        f.load("a\n" + String(repeating: "x", count: 300) + "\nzzz", "a\n新增的一行\n" + String(repeating: "x", count: 300) + "\nzzz")
        f.window.makeFirstResponder(f.left)
        f.left.selectAll(nil)
        f.left.deleteBackward(nil)
        f.draw()
    }

    @Test func resizeWithStaleComparisonDoesNotCrash() async {
        let f = EditorFixture()
        f.load("a\nb\n" + String(repeating: "word ", count: 200), "a\nnew\nb\n" + String(repeating: "word ", count: 200))
        f.window.makeFirstResponder(f.left)
        f.left.selectAll(nil)
        f.left.insertText("a\nb", replacementRange: f.left.selectedRange())
        await f.resize(width: 700)
        f.draw()
    }

    @Test func undoAfterReplaceRestoresText() {
        let f = EditorFixture()
        f.window.makeFirstResponder(f.left)
        let undo = f.left.undoManager!
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        f.left.insertText("hello world", replacementRange: NSRange(location: 0, length: 0))
        f.left.breakUndoCoalescing()
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        f.coordinator.replace(f.left, with: "")
        undo.endUndoGrouping()
        undo.undo()
        #expect(f.left.string == "hello world")
    }

    @Test func emptyEditorAcceptsClicks() {
        let f = EditorFixture()
        f.load("", "")
        let point = f.coordinator.leftScroll.convert(NSPoint(x: 100, y: 450), to: nil)
        let hit = f.window.contentView!.hitTest(f.window.contentView!.superview!.convert(point, from: nil))
        #expect(hit === f.left)
    }

    @Test func copyMatchesPastedText() {
        let f = EditorFixture()
        let text = "第一行 \"引號\" -- 破折號\r\n😀 第二行\n\(longLine)"
        f.load(text, "新增\n" + text)
        f.window.makeFirstResponder(f.left)
        f.left.selectAll(nil)
        f.left.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == text)
    }

    @Test func noAutomaticSubstitution() {
        let f = EditorFixture()
        f.window.makeFirstResponder(f.left)
        for ch in "\"test\" -- 'a'" { f.left.insertText(String(ch), replacementRange: f.left.selectedRange()) }
        #expect(f.left.string == "\"test\" -- 'a'")
    }

    @Test func typingInsideHighlightIsNotHighlighted() {
        let f = EditorFixture()
        let result = f.load("今天天氣很好", "今天天氣不好")
        let changed = try! #require(result.rightHighlights.first { $0.kind == .textInserted })
        f.window.makeFirstResponder(f.right)
        f.right.setSelectedRange(NSRange(location: NSMaxRange(changed.range), length: 0))
        f.right.insertText("真", replacementRange: f.right.selectedRange())
        let typed = f.right.textStorage!.attributes(at: NSMaxRange(changed.range), effectiveRange: nil)
        #expect(typed[.backgroundColor] == nil)
        #expect(typed[.toolTip] == nil)
    }

    @Test func lineNumbersSitAtEachLineTop() {
        let f = EditorFixture()
        let result = f.load("開頭\n\(longLine)\n結尾", "新增的標題\n開頭\n\(longLine)\n結尾")
        #expect(f.coordinator.leftScroll.rulersVisible && f.coordinator.leftScroll.verticalRulerView is LineNumberRuler)
        let numbers = f.left.lineNumberPositions(in: f.left.bounds)
        #expect(numbers.map(\.number) == [1, 2, 3])
        #expect(numbers.map(\.y) == result.leftLines.map { f.top(f.left, $0) })
    }

    @Test func jumpKeepsTextClearOfRuler() {
        let f = EditorFixture()
        let para = "這是一段會被搬到最後面的長段落"
        let filler = (0..<120).map { "第 \($0) 行" }.joined(separator: "\n")
        let result = f.load("\(para)\n\(filler)", "\(filler)\n\(para)")
        let move = try! #require(result.moves.first)
        _ = f.coordinator.jumpToCounterpart(from: f.right, at: result.rightLines[move.right].location)
        for scroll in [f.coordinator.leftScroll, f.coordinator.rightScroll] {
            let ruler = try! #require(scroll.verticalRulerView)
            #expect(scroll.convert(NSPoint.zero, from: scroll.documentView).x >= ruler.frame.maxX)
        }
    }

    @Test func commandClickJumpsToMovedCounterpart() {
        let f = EditorFixture()
        let para = "這是一段會被搬到最後面的長段落"
        let filler = (0..<120).map { "第 \($0) 行" }.joined(separator: "\n")
        let result = f.load("\(para)\n\(filler)", "\(filler)\n\(para)")
        let move = try! #require(result.moves.first)
        #expect(f.coordinator.jumpToCounterpart(from: f.left, at: result.leftLines[move.left].location))
        let visible = f.coordinator.rightScroll.contentView.documentVisibleRect
        #expect(visible.contains(NSPoint(x: 10, y: f.top(f.right, result.rightLines[move.right]))))
        #expect(!f.coordinator.jumpToCounterpart(from: f.left, at: result.leftLines[1].location))
    }

    @Test func writingToolsDisabled() {
        let f = EditorFixture()
        #expect(f.left.writingToolsBehavior == .none && f.left.inlinePredictionType == .no)
    }

    @Test func scrollingIsSynced() {
        let f = EditorFixture()
        let text = (0..<200).map { "第 \($0) 行" }.joined(separator: "\n")
        f.load(text, text)
        f.coordinator.leftScroll.contentView.scroll(to: NSPoint(x: 0, y: 1200))
        #expect(f.coordinator.rightScroll.contentView.bounds.origin.y == 1200)
    }

    @Test func movedLinesHaveTooltips() {
        let f = EditorFixture()
        let para = "這是一段會被搬到最後面的長段落"
        let result = f.load("\(para)\n第二行內容\n第三行內容", "第二行內容\n第三行內容\n\(para)")
        let move = try! #require(result.moves.first)
        let tip = f.left.textStorage!.attribute(.toolTip, at: result.leftLines[move.left].location, effectiveRange: nil) as? String
        #expect(tip?.contains("新版第 3 行") == true)
    }
}
