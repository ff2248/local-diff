import AppKit
import DiffCore
import Testing
@testable import DiffEditor

private let longLine = String(repeating: "這一行很長，會在窄的視窗裡自動換成好幾行。", count: 8)

@MainActor
@Suite(.serialized)
struct EditorStyleTests {
    @Test func lineHeightScalesWithFontSize() {
        #expect(EditorStyle.default.fontSize == 13 && EditorStyle.default.lineHeight == 20)
        #expect(EditorStyle(fontSize: 18).lineHeight == 28)
        #expect(EditorStyle.fontSizes == 10...24)
    }

    @Test func changingFontSizeKeepsLinesEvenAndAligned() {
        let f = EditorFixture()
        let result = f.load("開頭\n\(longLine)\n中間\n結尾", "開頭\n新增的一行\n\(longLine)改\n中間\n結尾")
        let style = EditorStyle(fontSize: 18)
        f.coordinator.setStyle(style)
        #expect(f.misalignedRows(result) == 0)
        #expect(f.top(f.left, result.leftLines[3]) - f.top(f.left, result.leftLines[2]) == style.lineHeight)
        #expect(f.left.font?.pointSize == 18)
    }

    @Test func unwrappedLinesStayOnOneRowAndScrollTogether() {
        let f = EditorFixture()
        f.coordinator.setStyle(EditorStyle(fontSize: 13, wrapsLines: false))
        let result = f.load("開頭\n\(longLine)\n結尾", "開頭\n\(longLine)\n結尾")
        let tops = result.leftLines.map { f.top(f.left, $0) }
        #expect(tops[2] - tops[1] == EditorStyle.default.lineHeight)
        #expect(f.left.frame.width > f.coordinator.leftScroll.contentSize.width)
        #expect(f.coordinator.leftScroll.hasHorizontalScroller)
        let left = f.coordinator.leftScroll.contentView
        left.scroll(to: NSPoint(x: 200 - left.contentInsets.left, y: 0))
        let right = f.coordinator.rightScroll.contentView
        #expect(right.bounds.origin.x + right.contentInsets.left == 200)
    }

    @Test func unwrappedPanesShareOneWidthAtLeastTheVisibleArea() {
        let f = EditorFixture()
        f.coordinator.setStyle(EditorStyle(fontSize: 13, wrapsLines: false))
        f.load("abc\n\(longLine)", "abc\nxyz")
        #expect(f.left.frame.width == f.right.frame.width)
        f.coordinator.replace(f.left, with: "")
        f.coordinator.replace(f.right, with: "")
        f.load("", "")
        for (view, scroll) in [(f.left, f.coordinator.leftScroll), (f.right, f.coordinator.rightScroll)] {
            #expect(view.frame.width >= scroll.contentSize.width - scroll.contentView.contentInsets.left)
        }
    }

    @Test func horizontalSyncStaysInsideTheOtherPane() {
        let f = EditorFixture()
        f.coordinator.setStyle(EditorStyle(fontSize: 13, wrapsLines: false))
        f.load("\(longLine)\(longLine)", "short")
        let left = f.coordinator.leftScroll.contentView
        left.scroll(to: NSPoint(x: f.left.frame.width - left.bounds.width, y: 0))
        let right = f.coordinator.rightScroll.contentView
        #expect(right.bounds.maxX <= f.right.frame.width + 0.5)
    }

    @Test func rulerFitsLineNumbersAtLargeFontSizes() {
        let f = EditorFixture()
        f.coordinator.setStyle(EditorStyle(fontSize: 24))
        let text = (0..<150).map { "line \($0)" }.joined(separator: "\n")
        f.load(text, text)
        let ruler = try! #require(f.coordinator.leftScroll.verticalRulerView)
        let label = ("150" as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .regular)])
        #expect(ruler.ruleThickness - label.width - 8 >= 0)
    }

    @Test func outOfRangeSettingsAreClamped() {
        #expect(EditorStyle(fontSize: 0).fontSize == 10)
        #expect(EditorStyle(fontSize: 99).fontSize == 24)
        #expect(EditorStyle(fontSize: 13.6).fontSize == 14)
        let lines = (0..<30).map { "第 \($0) 行的內容" }
        let changed = lines.enumerated().map { $0 == 15 ? "第 15 行改過了" : $1 }
        let f = EditorFixture()
        f.coordinator.setCollapseUnchanged(true)
        f.load(lines.joined(separator: "\n"), changed.joined(separator: "\n"))
        f.coordinator.setContextLines(-100)
        #expect(f.left.folds.map(\.lineCount) == [15, 14])
    }

    @Test func wrappingCanBeTurnedBackOn() {
        let f = EditorFixture()
        f.coordinator.setStyle(EditorStyle(fontSize: 13, wrapsLines: false))
        let result = f.load("開頭\n\(longLine)\n結尾", "開頭\n\(longLine)\n結尾")
        f.coordinator.setStyle(.default)
        #expect(f.left.frame.width <= f.coordinator.leftScroll.contentSize.width)
        #expect(f.top(f.left, result.leftLines[2]) - f.top(f.left, result.leftLines[1]) > EditorStyle.default.lineHeight)
    }

    @Test func contextLinesAroundChangesAreConfigurable() {
        let lines = (0..<30).map { "第 \($0) 行的內容" }
        let changed = lines.enumerated().map { $0 == 15 ? "第 15 行改過了" : $1 }
        let f = EditorFixture()
        f.coordinator.setCollapseUnchanged(true)
        f.load(lines.joined(separator: "\n"), changed.joined(separator: "\n"))
        #expect(f.left.folds.map(\.lineCount) == [12, 11])
        f.coordinator.setContextLines(1)
        #expect(f.left.folds.map(\.lineCount) == [14, 13])
    }
}
