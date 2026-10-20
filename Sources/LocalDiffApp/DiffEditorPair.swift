import AppKit
import DiffCore
import SwiftUI

struct DiffEditorPair: NSViewRepresentable {
    @Binding var left: String
    @Binding var right: String
    let comparison: Comparison?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSStackView {
        let c = context.coordinator
        let stack = NSStackView(views: [c.leftScroll, c.rightScroll])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        return stack
    }

    func updateNSView(_ view: NSStackView, context: Context) {
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
    final class Coordinator: NSObject, NSTextViewDelegate {
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

        func textDidChange(_ notification: Notification) {
            guard !isReplacing, let tv = notification.object as? DiffTextView else { return }
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
            leftView.applyTooltips(result.moves.map { (result.leftLines[$0.left], "已移到新版第 \($0.right + 1) 行") })
            rightView.applyTooltips(result.moves.map { (result.rightLines[$0.right], "從舊版第 \($0.left + 1) 行移來") })
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
        }

        private func equalizeHeights() {
            let height = max(leftView.contentHeight, rightView.contentHeight,
                             leftScroll.contentSize.height, rightScroll.contentSize.height)
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
        }

        private static func scrollView(for textView: NSTextView) -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.documentView = textView
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

        font = .monospacedSystemFont(ofSize: 13, weight: .regular)
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
        storage.setAttributes([.font: font as Any, .foregroundColor: NSColor.textColor],
                              range: NSRange(location: 0, length: storage.length))
        didChangeText()
        lineHighlights = []
        paddingByLocation = [:]
        topPadding = 0
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
        storage.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: storage.length))
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
            let style = NSMutableParagraphStyle()
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
        guard let layout = layoutManager, let container = textContainer else { return }
        let origin = textContainerOrigin.y

        let length = (string as NSString).length
        NSColor.secondaryLabelColor.withAlphaComponent(0.06).setFill()
        if topPadding > 0 {
            NSRect(x: 0, y: textContainerInset.height, width: bounds.width, height: topPadding).fill()
        }
        for (location, pad) in paddingByLocation where location <= length {
            let top = fragmentsRect(for: NSRange(location: location, length: 0)).minY + origin
            NSRect(x: 0, y: top, width: bounds.width, height: pad).fill()
        }
        let end = layout.usedRect(for: container).maxY + origin
        if end < bounds.maxY - textContainerInset.height {
            NSRect(x: 0, y: end, width: bounds.width, height: bounds.maxY - textContainerInset.height - end).fill()
        }

        for h in lineHighlights where NSMaxRange(h.range) <= length {
            var box = fragmentsRect(for: h.range)
            let pad = paddingByLocation[h.range.location] ?? 0
            box.origin.y += origin + pad
            box.size.height -= pad
            box.origin.x = 0
            box.size.width = bounds.width
            guard box.intersects(rect) else { continue }
            color(for: h.kind).setFill()
            box.fill()
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
        case .lineDeleted: .systemRed.withAlphaComponent(0.12)
        case .lineInserted: .systemGreen.withAlphaComponent(0.12)
        case .lineModified: (side == .left ? NSColor.systemRed : .systemGreen).withAlphaComponent(0.12)
        case .lineMoved: .systemPurple.withAlphaComponent(0.15)
        case .textDeleted: .systemRed.withAlphaComponent(0.4)
        case .textInserted: .systemGreen.withAlphaComponent(0.4)
        }
    }
}
