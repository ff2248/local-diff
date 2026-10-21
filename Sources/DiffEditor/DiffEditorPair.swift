import AppKit
import DiffCore
import SwiftUI

public struct Comparison: Sendable {
    public let generation: Int
    public let left: String
    public let right: String
    public let result: DiffResult

    public init(generation: Int, left: String, right: String, result: DiffResult) {
        self.generation = generation
        self.left = left
        self.right = right
        self.result = result
    }
}

public struct DiffEditorPair: NSViewRepresentable {
    @Binding var left: String
    @Binding var right: String
    let comparison: Comparison?

    public init(left: Binding<String>, right: Binding<String>, comparison: Comparison?) {
        _left = left
        _right = right
        self.comparison = comparison
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSStackView {
        let c = context.coordinator
        let stack = NSStackView(views: [c.leftScroll, c.rightScroll])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        return stack
    }

    public func updateNSView(_ view: NSStackView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.replace(c.leftView, with: left)
        c.replace(c.rightView, with: right)
        if let comparison, comparison.generation != c.appliedGeneration,
           c.leftView.string == comparison.left, c.rightView.string == comparison.right {
            c.apply(comparison)
            c.appliedGeneration = comparison.generation
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DiffEditorPair
        var appliedGeneration = -1
        let leftView = DiffTextView(side: .left)
        let rightView = DiffTextView(side: .right)
        let leftScroll: NSScrollView
        let rightScroll: NSScrollView
        private var comparison: Comparison?
        private var isReplacing = false
        private var alignedWidths: (CGFloat, CGFloat) = (0, 0)
        private var alignScheduled = false
        private var syncingScroll = false

        init(_ parent: DiffEditorPair) {
            self.parent = parent
            leftScroll = Self.scrollView(for: leftView)
            rightScroll = Self.scrollView(for: rightView)
            super.init()
            leftView.delegate = self
            rightView.delegate = self
            leftView.onCommandClick = { [unowned self] in jumpToCounterpart(from: $0, at: $1) }
            rightView.onCommandClick = { [unowned self] in jumpToCounterpart(from: $0, at: $1) }
            for view in [leftView, rightView] {
                view.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(frameChanged),
                                                       name: NSView.frameDidChangeNotification, object: view)
            }
            for scroll in [leftScroll, rightScroll] {
                scroll.contentView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                                       name: NSView.boundsDidChangeNotification, object: scroll.contentView)
                scroll.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(scrollResized),
                                                       name: NSView.frameDidChangeNotification, object: scroll)
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? DiffTextView else { return }
            refreshRuler(of: tv)
            guard !isReplacing else { return }
            if tv === leftView { parent.left = tv.string } else { parent.right = tv.string }
        }

        func replace(_ view: DiffTextView, with text: String) {
            guard view.string != text else { return }
            isReplacing = true
            view.replaceText(with: text)
            isReplacing = false
        }

        func apply(_ comparison: Comparison) {
            self.comparison = comparison
            let result = comparison.result
            leftView.apply(result.leftHighlights)
            rightView.apply(result.rightHighlights)
            leftView.applyTooltips(result.moves.map { (result.leftLines[$0.left], "已移到新版第 \($0.right + 1) 行，⌘ 點一下跳過去") })
            rightView.applyTooltips(result.moves.map { (result.rightLines[$0.right], "從舊版第 \($0.left + 1) 行移來，⌘ 點一下跳過去") })
            align()
        }

        private func align() {
            guard let comparison, leftView.string == comparison.left, rightView.string == comparison.right else { return }
            let result = comparison.result
            alignedWidths = (leftView.frame.width, rightView.frame.width)
            let leftHeights = leftView.resetPadding(lines: result.leftLines)
            let rightHeights = rightView.resetPadding(lines: result.rightLines)
            let padding = alignmentPadding(rows: result.rows, leftHeights: leftHeights, rightHeights: rightHeights)
            leftView.applyPadding(padding.left, lines: result.leftLines)
            rightView.applyPadding(padding.right, lines: result.rightLines)
            equalizeHeights()
            refreshRuler(of: leftView)
            refreshRuler(of: rightView)
        }

        func jumpToCounterpart(from view: DiffTextView, at index: Int) -> Bool {
            guard let comparison, leftView.string == comparison.left, rightView.string == comparison.right else { return false }
            let result = comparison.result
            let fromLeft = view === leftView
            let ownLines = fromLeft ? result.leftLines : result.rightLines
            guard let move = result.moves.first(where: { move in
                let line = ownLines[fromLeft ? move.left : move.right]
                return index >= line.location && index <= NSMaxRange(line)
            }) else { return false }
            let target = fromLeft ? rightView : leftView
            let targetScroll = fromLeft ? rightScroll : leftScroll
            let line = (fromLeft ? result.rightLines : result.leftLines)[fromLeft ? move.right : move.left]
            let maxY = max(0, target.frame.height - targetScroll.contentSize.height)
            let y = min(max(0, target.lineTop(line) - 80), maxY)
            targetScroll.contentView.scroll(to: NSPoint(x: targetScroll.contentView.bounds.origin.x, y: y))
            targetScroll.reflectScrolledClipView(targetScroll.contentView)
            target.showFindIndicator(for: line)
            return true
        }

        private func refreshRuler(of view: DiffTextView) {
            let scroll = view === leftView ? leftScroll : rightScroll
            guard let ruler = scroll.verticalRulerView as? LineNumberRuler else { return }
            ruler.updateThickness(lineCount: view.lineCount)
            ruler.needsDisplay = true
        }

        private func equalizeHeights() {
            let content = max(leftView.contentHeight, rightView.contentHeight)
            leftView.alignedContentHeight = content
            rightView.alignedContentHeight = content
            let height = max(content, leftScroll.contentSize.height, rightScroll.contentSize.height)
            leftView.setMinimumHeight(height)
            rightView.setMinimumHeight(height)
        }

        @objc private func scrollResized(_ notification: Notification) {
            equalizeHeights()
        }

        @objc private func frameChanged(_ notification: Notification) {
            guard comparison != nil, !alignScheduled,
                  (leftView.frame.width, rightView.frame.width) != alignedWidths else { return }
            alignScheduled = true
            DispatchQueue.main.async { [self] in
                alignScheduled = false
                align()
            }
        }

        @objc private func scrolled(_ notification: Notification) {
            guard !syncingScroll, let source = notification.object as? NSClipView else { return }
            let target = source === leftScroll.contentView ? rightScroll : leftScroll
            syncingScroll = true
            target.contentView.scroll(to: NSPoint(x: target.contentView.bounds.origin.x, y: source.bounds.origin.y))
            target.reflectScrolledClipView(target.contentView)
            syncingScroll = false
            leftScroll.verticalRulerView?.needsDisplay = true
            rightScroll.verticalRulerView?.needsDisplay = true
        }

        private static func scrollView(for textView: DiffTextView) -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.documentView = textView
            scroll.verticalRulerView = LineNumberRuler(textView: textView, scrollView: scroll)
            scroll.hasVerticalRuler = true
            scroll.rulersVisible = true
            return scroll
        }
    }
}

final class DiffTextView: NSTextView {
    enum Side { case left, right }

    let side: Side
    private var lineHighlights: [Highlight] = []
    private var paddingByLocation: [Int: CGFloat] = [:]
    // TextKit 1 不套用第一段的 paragraphSpacingBefore，第一行的補白改由 textContainerOrigin 往下推。
    private var topPadding: CGFloat = 0
    var onCommandClick: ((DiffTextView, Int) -> Bool)?
    /// 兩側內容較高者的高度，文末補白只畫到這裡。
    var alignedContentHeight: CGFloat = 0

    init(side: Side) {
        self.side = side
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)

        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        writingToolsBehavior = .none
        inlinePredictionType = .no

        font = Theme.font
        textColor = Theme.text
        backgroundColor = Theme.background
        defaultParagraphStyle = Theme.paragraphStyle
        typingAttributes = Theme.textAttributes
        textContainerInset = NSSize(width: 8, height: 8)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y + topPadding)
    }

    var lineCount: Int {
        var count = 0
        (string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (string as NSString).length),
                                                 options: [.byLines, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }

    /// 某行第一個字的頂端，座標是文字框本身的座標系。
    func lineTop(_ line: NSRange) -> CGFloat {
        guard let layout = layoutManager else { return 0 }
        let glyph = layout.glyphIndexForCharacter(at: min(line.location, max(0, (string as NSString).length - 1)))
        return layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).minY + textContainerOrigin.y
    }

    /// rect 範圍內每一行的行號（從 1 起算）與頂端位置。
    func lineNumberPositions(in rect: NSRect) -> [(number: Int, y: CGFloat)] {
        guard let layout = layoutManager, let container = textContainer else { return [] }
        let ns = string as NSString
        guard ns.length > 0 else { return [] }
        let containerRect = rect.offsetBy(dx: 0, dy: -textContainerOrigin.y)
        let glyphs = layout.glyphRange(forBoundingRect: containerRect, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let start = ns.lineRange(for: NSRange(location: min(chars.location, ns.length), length: 0)).location
        var number = 1
        ns.enumerateSubstrings(in: NSRange(location: 0, length: start),
                               options: [.byLines, .substringNotRequired]) { _, _, _, _ in number += 1 }
        var result: [(number: Int, y: CGFloat)] = []
        let end = min(ns.length, NSMaxRange(chars) + 1)
        ns.enumerateSubstrings(in: NSRange(location: start, length: end - start),
                               options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            result.append((number, self.lineTop(range)))
            number += 1
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let onCommandClick,
           onCommandClick(self, characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))) {
            return
        }
        super.mouseDown(with: event)
    }

    var contentHeight: CGFloat {
        guard let layout = layoutManager, let container = textContainer else { return 0 }
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height + topPadding + textContainerInset.height * 2
    }

    /// 以可 undo 的方式整段取代文字，並清掉舊比對留下的樣式。
    func replaceText(with text: String) {
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard shouldChangeText(in: full, replacementString: text) else { return }
        storage.replaceCharacters(in: full, with: text)
        storage.setAttributes(Theme.textAttributes, range: NSRange(location: 0, length: storage.length))
        didChangeText()
        lineHighlights = []
        paddingByLocation = [:]
        topPadding = 0
        alignedContentHeight = 0
        invalidateTextContainerOrigin()
    }

    func apply(_ highlights: [Highlight]) {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
        for h in highlights where h.kind == .textDeleted || h.kind == .textInserted {
            storage.addAttribute(.backgroundColor, value: color(for: h.kind), range: h.range)
        }
        storage.endEditing()
        lineHighlights = highlights.filter { $0.kind != .textDeleted && $0.kind != .textInserted }
        needsDisplay = true
    }

    func applyTooltips(_ tips: [(NSRange, String)]) {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.removeAttribute(.toolTip, range: NSRange(location: 0, length: storage.length))
        for (range, tip) in tips { storage.addAttribute(.toolTip, value: tip, range: range) }
        storage.endEditing()
    }

    /// 清除對齊用的段落間距，回傳每行換行後的自然高度。
    func resetPadding(lines: [NSRange]) -> [CGFloat] {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return [] }
        storage.beginEditing()
        storage.addAttribute(.paragraphStyle, value: Theme.paragraphStyle, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        paddingByLocation = [:]
        topPadding = 0
        invalidateTextContainerOrigin()
        layout.ensureLayout(for: container)
        return lines.map { fragmentsRect(for: $0).height }
    }

    func applyPadding(_ padding: [CGFloat], lines: [NSRange]) {
        guard let storage = textStorage else { return }
        let ns = string as NSString
        storage.beginEditing()
        topPadding = lines.isEmpty ? 0 : padding[0]
        invalidateTextContainerOrigin()
        for (i, line) in lines.enumerated().dropFirst() where padding[i] > 0 {
            let style = Theme.paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            style.paragraphSpacingBefore = padding[i]
            storage.addAttribute(.paragraphStyle, value: style, range: ns.lineRange(for: line))
            paddingByLocation[line.location] = padding[i]
        }
        storage.endEditing()
        needsDisplay = true
    }

    func setMinimumHeight(_ height: CGFloat) {
        minSize = NSSize(width: 0, height: height)
        sizeToFit()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        Theme.filler.setFill()
        fillerRects().forEach { $0.fill() }
        for (box, kind) in highlightedLineRects() where box.intersects(rect) {
            color(for: kind).setFill()
            box.fill()
        }
    }

    /// 對齊用的補白區塊，座標是文字框本身的座標系。
    func fillerRects() -> [NSRect] {
        guard let layout = layoutManager, let container = textContainer else { return [] }
        let origin = textContainerOrigin.y
        let length = (string as NSString).length
        var rects: [NSRect] = []
        if topPadding > 0 {
            rects.append(NSRect(x: 0, y: textContainerInset.height, width: bounds.width, height: topPadding))
        }
        for (location, pad) in paddingByLocation where location <= length {
            let top = fragmentsRect(for: NSRange(location: location, length: 0)).minY + origin
            rects.append(NSRect(x: 0, y: top, width: bounds.width, height: pad))
        }
        let end = layout.usedRect(for: container).maxY + origin
        let alignedEnd = alignedContentHeight - textContainerInset.height
        if end < alignedEnd {
            rects.append(NSRect(x: 0, y: end, width: bounds.width, height: alignedEnd - end))
        }
        return rects
    }

    /// 有整行底色的行（不含補白），座標是文字框本身的座標系。
    func highlightedLineRects() -> [(NSRect, HighlightKind)] {
        let origin = textContainerOrigin.y
        let length = (string as NSString).length
        return lineHighlights.filter { NSMaxRange($0.range) <= length }.map { h in
            var box = fragmentsRect(for: h.range)
            let pad = paddingByLocation[h.range.location] ?? 0
            box.origin.y += origin + pad
            box.size.height -= pad
            box.origin.x = 0
            box.size.width = bounds.width
            return (box, h.kind)
        }
    }

    private func fragmentsRect(for line: NSRange) -> NSRect {
        guard let layout = layoutManager else { return .zero }
        let chars = (string as NSString).lineRange(for: line)
        if chars.length == 0 { return layout.extraLineFragmentRect }
        let glyphs = layout.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
        var box = NSRect.null
        layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in box = box.union(rect) }
        return box
    }

    private func color(for kind: HighlightKind) -> NSColor {
        switch kind {
        case .lineDeleted: Theme.deletedLine
        case .lineInserted: Theme.insertedLine
        case .lineModified: side == .left ? Theme.deletedLine : Theme.insertedLine
        case .lineMoved: Theme.movedLine
        case .textDeleted: Theme.deletedWord
        case .textInserted: Theme.insertedWord
        }
    }
}
