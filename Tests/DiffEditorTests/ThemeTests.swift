import AppKit
import Testing
@testable import DiffEditor

@MainActor
private func hex(_ color: NSColor, _ name: NSAppearance.Name) -> String {
    var result = ""
    NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        let c = color.usingColorSpace(.sRGB)!
        let parts = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
        result = parts.map { String(format: "%02x", $0) }.joined()
    }
    return result
}

@MainActor
@Suite(.serialized)
struct ThemeTests {
    @Test func lightMatchesGitHub() {
        #expect(hex(Theme.background, .aqua) == "ffffffff")
        #expect(hex(Theme.text, .aqua) == "1f2328ff")
        #expect(hex(Theme.deletedLine, .aqua) == "ffebe9ff")
        #expect(hex(Theme.deletedWord, .aqua) == "ffcecbff")
        #expect(hex(Theme.insertedLine, .aqua) == "dafbe1ff")
        #expect(hex(Theme.insertedWord, .aqua) == "aceebbff")
        #expect(hex(Theme.filler, .aqua) == "f6f8faff")
        #expect(hex(Theme.lineNumber, .aqua) == "59636eff")
        #expect(hex(Theme.movedLine, .aqua) == "fbefffff")
    }

    @Test func darkMatchesGitHub() {
        #expect(hex(Theme.background, .darkAqua) == "0d1117ff")
        #expect(hex(Theme.text, .darkAqua) == "f0f6fcff")
        #expect(hex(Theme.deletedLine, .darkAqua) == "f851491a")
        #expect(hex(Theme.deletedWord, .darkAqua) == "f8514966")
        #expect(hex(Theme.insertedLine, .darkAqua) == "2ea04326")
        #expect(hex(Theme.insertedWord, .darkAqua) == "2ea04366")
        #expect(hex(Theme.filler, .darkAqua) == "151b23ff")
        #expect(hex(Theme.lineNumber, .darkAqua) == "9198a1ff")
        #expect(hex(Theme.movedLine, .darkAqua) == "ab7df826")
    }

    @Test func linesAreEvenlySpaced() {
        let f = EditorFixture()
        let result = f.load("abc\n中文內容\nabc\n😀", "abc")
        let tops = result.leftLines.map { f.top(f.left, $0) }
        #expect(zip(tops, tops.dropFirst()).allSatisfy { $1 - $0 == Theme.lineHeight })
        #expect(Theme.lineHeight == 20)
    }

    @Test func noFillerBelowEqualLengthTexts() {
        let f = EditorFixture()
        f.load("第一行\n第二行內容\nabc", "第一行\n新增\nabc")
        #expect(f.left.fillerRects().isEmpty && f.right.fillerRects().isEmpty)
    }

    @Test func trailingFillerOnlyCoversMissingLines() {
        let f = EditorFixture()
        f.load("a\nb", "a\nb\nc\nd")
        let filler = try! #require(f.left.fillerRects().first)
        #expect(f.left.fillerRects().count == 1 && filler.height == 2 * Theme.lineHeight)
    }

    @Test func wholeEditorRendersBothSides() {
        let f = EditorFixture()
        f.load("第一行\n第二行內容\nabc", "第一行\n新增\nabc")
        let stack = f.window.contentView!
        let rep = stack.bitmapImageRepForCachingDisplay(in: stack.bounds)!
        stack.cacheDisplay(in: stack.bounds, to: rep)
        func pixel(in view: DiffTextView) -> NSColor {
            let box = view.highlightedLineRects().first!.0
            let point = stack.convert(NSPoint(x: box.maxX - 20, y: box.midY), from: view)
            let scale = CGFloat(rep.pixelsWide) / stack.bounds.width
            let y = stack.isFlipped ? point.y : stack.bounds.height - point.y
            return rep.colorAt(x: Int(point.x * scale), y: Int(y * scale))!.usingColorSpace(.sRGB)!
        }
        let deleted = pixel(in: f.left)
        let inserted = pixel(in: f.right)
        #expect(deleted.redComponent > deleted.greenComponent)
        #expect(inserted.greenComponent > inserted.redComponent)
    }

    @Test func typedTextKeepsLineHeight() {
        let f = EditorFixture()
        f.load("abc", "abc")
        f.window.makeFirstResponder(f.left)
        f.left.setSelectedRange(NSRange(location: 3, length: 0))
        f.left.insertText("\n中文", replacementRange: f.left.selectedRange())
        let lines = [NSRange(location: 0, length: 3), NSRange(location: 4, length: 2)]
        #expect(f.top(f.left, lines[1]) - f.top(f.left, lines[0]) == Theme.lineHeight)
    }
}
