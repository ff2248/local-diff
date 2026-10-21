import AppKit
import DiffCore
import SwiftUI
@testable import DiffEditor

@MainActor
final class EditorFixture {
    let coordinator: DiffEditorPair.Coordinator
    let window: NSWindow
    private let stack: NSStackView
    private var generation = 0

    var left: DiffTextView { coordinator.leftView }
    var right: DiffTextView { coordinator.rightView }

    init(width: CGFloat = 1000) {
        _ = NSApplication.shared
        coordinator = DiffEditorPair.Coordinator(DiffEditorPair(left: .constant(""), right: .constant(""), comparison: nil))
        stack = NSStackView(views: [coordinator.leftScroll, coordinator.rightScroll])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = stack
        stack.layoutSubtreeIfNeeded()
    }

    @discardableResult
    func load(_ l: String, _ r: String, options: CompareOptions = CompareOptions()) -> DiffResult {
        coordinator.replace(left, with: l)
        coordinator.replace(right, with: r)
        let result = computeDiff(left: l, right: r, options: options)
        generation += 1
        stack.layoutSubtreeIfNeeded()
        coordinator.apply(Comparison(generation: generation, left: l, right: r, result: result))
        stack.layoutSubtreeIfNeeded()
        return result
    }

    func resize(width: CGFloat) async {
        window.setContentSize(NSSize(width: width, height: 900))
        stack.layoutSubtreeIfNeeded()
        await settle()
    }

    /// 讓出 main queue，讓 DispatchQueue.main.async 排入的對齊重算跑完。
    func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// 觸發完整繪製，drawBackground 有問題時會在這裡 crash。
    func draw() {
        let rep = stack.bitmapImageRepForCachingDisplay(in: stack.bounds)!
        stack.cacheDisplay(in: stack.bounds, to: rep)
    }

    /// 某行第一個字在文字框座標系中的頂端位置。摺疊起來的行以摺疊標示的位置為準。
    func top(_ view: NSTextView, _ line: NSRange) -> CGFloat {
        if let diffView = view as? DiffTextView,
           let marker = diffView.foldMarkerRects().first(where: { NSLocationInRange(line.location, $0.fold.hidden) }) {
            return marker.rect.minY
        }
        let layout = view.layoutManager!
        let glyphs = layout.glyphRange(forCharacterRange: line, actualCharacterRange: nil)
        return layout.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil).minY + view.textContainerOrigin.y
    }

    func misalignedRows(_ result: DiffResult) -> Int {
        result.rows.filter { row in
            guard let l = row.left, let r = row.right else { return false }
            return abs(top(left, result.leftLines[l]) - top(right, result.rightLines[r])) > 0.5
        }.count
    }
}

func temporaryFile(_ bytes: [UInt8], name: String = "sample.txt") -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try! Data(bytes).write(to: url)
    return url
}
