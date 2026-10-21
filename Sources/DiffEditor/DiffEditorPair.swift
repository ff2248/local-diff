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
    let collapseUnchanged: Bool

    public init(left: Binding<String>, right: Binding<String>, comparison: Comparison?, collapseUnchanged: Bool = false) {
        _left = left
        _right = right
        self.comparison = comparison
        self.collapseUnchanged = collapseUnchanged
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
        c.setCollapseUnchanged(collapseUnchanged)
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
        private(set) var collapseUnchanged = false
        /// 使用者展開過的摺疊區（以左側行號範圍記錄），重新比對後與它重疊的區段維持展開。
        private var expandedRegions: [Range<Int>] = []

        init(_ parent: DiffEditorPair) {
            self.parent = parent
            leftScroll = Self.scrollView(for: leftView)
            rightScroll = Self.scrollView(for: rightView)
            super.init()
            leftView.delegate = self
            rightView.delegate = self
            for view in [leftView, rightView] {
                view.onCommandClick = { [unowned self] in jumpToCounterpart(from: $0, at: $1) }
                view.onRevealFold = { [unowned self] in reveal($0) }
                view.onTextReplaced = { [unowned self] in expandedRegions = [] }
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

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? DiffTextView,
                  let entered = tv.fold(holdingSelectionAmong: tv.folds) ?? tv.tailFoldAtCaret() else { return }
            reveal(entered)
        }

        func setCollapseUnchanged(_ on: Bool) {
            guard on != collapseUnchanged else { return }
            collapseUnchanged = on
            expandedRegions = []
            leftView.setFolds([])
            rightView.setFolds([])
            align()
        }

        func reveal(_ fold: DiffTextView.Fold) {
            expandedRegions.append(fold.region)
            for view in [leftView, rightView] { view.setFolds(view.folds.filter { $0.region != fold.region }) }
            align()
        }

        private func applyFolds(_ result: DiffResult) {
            guard collapseUnchanged else { return }
            var leftFolds: [DiffTextView.Fold] = []
            var rightFolds: [DiffTextView.Fold] = []
            for rows in collapsibleRegions(rows: result.rows) {
                let lefts = result.rows[rows].compactMap(\.left)
                let rights = result.rows[rows].compactMap(\.right)
                let region = lefts.first!..<(lefts.last! + 1)
                guard !expandedRegions.contains(where: { $0.overlaps(region) }) else { continue }
                let leftFold = leftView.fold(lines: lefts.map { result.leftLines[$0] }, region: region)
                let rightFold = rightView.fold(lines: rights.map { result.rightLines[$0] }, region: region)
                if leftView.isEditing(within: leftFold) || rightView.isEditing(within: rightFold) {
                    expandedRegions.append(region)
                    continue
                }
                leftFolds.append(leftFold)
                rightFolds.append(rightFold)
            }
            leftView.setFolds(leftFolds)
            rightView.setFolds(rightFolds)
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
            applyFolds(result)
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

final class DiffTextView: NSTextView, @MainActor NSLayoutManagerDelegate, @MainActor NSTextStorageDelegate {
    enum Side { case left, right }

    /// 「只顯示差異」摺疊起來的連續未變動行。整段排成一行，畫「⋯ 未變動 N 行」標示。
    struct Fold: Hashable {
        var hidden: NSRange
        let lineCount: Int
        /// 這一段在左側的行號範圍，兩側對應的摺疊區共用同一個值。
        let region: Range<Int>
    }

    let side: Side
    private var lineHighlights: [Highlight] = []
    private var paddingByLocation: [Int: CGFloat] = [:]
    // TextKit 1 不套用第一段的 paragraphSpacingBefore，第一行的補白改由 textContainerOrigin 往下推。
    private var topPadding: CGFloat = 0
    var onCommandClick: ((DiffTextView, Int) -> Bool)?
    var onRevealFold: ((Fold) -> Void)?
    /// 整份內容被取代時呼叫（對調、清空、拖放、全選後貼上）。
    var onTextReplaced: (() -> Void)?
    private(set) var folds: [Fold] = []
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
        layout.delegate = self
        storage.delegate = self

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
        updateDragTypeRegistration()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 直接取 text storage 的字串。NSTextView.string 每次都會複製整份文字。
    private var text: NSString { textStorage?.mutableString ?? "" }

    override func updateDragTypeRegistration() {
        super.updateDragTypeRegistration()
        registerForDraggedTypes(registeredDraggedTypes + [.fileURL])
    }

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y + topPadding)
    }

    var lineCount: Int {
        var count = 0
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                                 options: [.byLines, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }

    /// 某行第一個字的頂端，座標是文字框本身的座標系。
    func lineTop(_ line: NSRange) -> CGFloat {
        guard let layout = layoutManager else { return 0 }
        let glyph = layout.glyphIndexForCharacter(at: min(line.location, max(0, text.length - 1)))
        return layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).minY + textContainerOrigin.y
    }

    /// rect 範圍內每一行的行號（從 1 起算）與頂端位置。
    func lineNumberPositions(in rect: NSRect) -> [(number: Int, y: CGFloat)] {
        guard let layout = layoutManager, let container = textContainer else { return [] }
        let ns = text
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
            if !self.isHidden(range.location) { result.append((number, self.lineTop(range))) }
            number += 1
        }
        return result
    }

    /// 用拖放的檔案取代這一側的內容，可以 undo。
    func loadDroppedFiles(_ urls: [URL]) throws(DroppedFile.LoadError) {
        replaceText(with: try DroppedFile.load(urls))
    }

    private static let fileURLsOnly: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    private func droppedFileURLs(_ sender: NSDraggingInfo) -> [URL]? {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: Self.fileURLsOnly) as? [URL]
        return urls?.isEmpty == false ? urls : nil
    }

    private func carriesFiles(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: Self.fileURLsOnly)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        carriesFiles(sender) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        carriesFiles(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = droppedFileURLs(sender) else { return super.performDragOperation(sender) }
        do {
            try loadDroppedFiles(urls)
        } catch {
            let alert = NSAlert()
            alert.messageText = error.message
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, let fold = fold(at: point) {
            onRevealFold?(fold)
            return
        }
        if event.modifierFlags.contains(.command), let onCommandClick,
           onCommandClick(self, characterIndexForInsertion(at: point)) {
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
        return lines.map { line in
            guard let fold = fold(containing: line.location) else { return fragmentsRect(for: line).height }
            return line.location == fold.hidden.location ? foldFragmentRect(fold).height : 0
        }
    }

    func applyPadding(_ padding: [CGFloat], lines: [NSRange]) {
        guard let storage = textStorage else { return }
        let ns = text
        storage.beginEditing()
        topPadding = lines.isEmpty ? 0 : padding[0]
        invalidateTextContainerOrigin()
        for (i, line) in lines.enumerated().dropFirst() where padding[i] > 0 {
            let style = Theme.paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            style.paragraphSpacingBefore = padding[i]
            // 摺疊區排成同一段，段落樣式中途改變會被拆成兩列，所以補白要套在整個摺疊區上。
            var range = ns.lineRange(for: line)
            if let fold = fold(containing: line.location), fold.hidden.location == line.location { range = fold.hidden }
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            paddingByLocation[line.location] = padding[i]
        }
        storage.endEditing()
        // 改了前面的段落樣式後，TextKit 只重排一部分，可能把摺疊區切成兩列，所以摺疊區要整段重排。
        for fold in folds where NSMaxRange(fold.hidden) <= storage.length {
            layoutManager?.invalidateLayout(forCharacterRange: fold.hidden, actualCharacterRange: nil)
        }
        needsDisplay = true
    }

    /// 由連續幾行組成一個摺疊區，範圍包含最後一行的換行字元。
    func fold(lines: [NSRange], region: Range<Int>) -> Fold {
        let ns = text
        let end = NSMaxRange(ns.lineRange(for: lines.last!))
        return Fold(hidden: NSRange(location: lines[0].location, length: end - lines[0].location),
                    lineCount: lines.count, region: region)
    }

    func setFolds(_ newFolds: [Fold]) {
        guard newFolds != folds else { return }
        let changed = Set(folds).symmetricDifference(newFolds)
        folds = newFolds
        guard let layout = layoutManager else { return }
        let length = textStorage?.length ?? 0
        for fold in changed where NSMaxRange(fold.hidden) <= length {
            layout.invalidateGlyphs(forCharacterRange: fold.hidden, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: fold.hidden, actualCharacterRange: nil)
        }
        needsDisplay = true
    }

    /// folds 依位置排序，用二分搜尋找包含 location 的摺疊區。
    private func fold(containing location: Int) -> Fold? {
        let index = firstFoldIndex(endingAfter: location)
        return index < folds.count && folds[index].hidden.location <= location ? folds[index] : nil
    }

    /// 第一個結尾在 location 之後的摺疊區索引。
    private func firstFoldIndex(endingAfter location: Int) -> Int {
        var low = 0
        var high = folds.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(folds[mid].hidden) <= location { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func isHidden(_ location: Int) -> Bool { fold(containing: location) != nil }

    /// 重排時摺疊區開頭的 .null 字形可能被算進前一行，所以用摺疊區最後一個字元（保留的換行）找它的那一列。
    private func foldFragmentRect(_ fold: Fold) -> NSRect {
        guard let layout = layoutManager else { return .zero }
        let glyph = layout.glyphIndexForCharacter(at: NSMaxRange(fold.hidden) - 1)
        return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    /// 摺疊標示的位置，座標是文字框本身的座標系。給 rect 時只算可能落在其中的摺疊區，前後各多算一個以涵蓋邊緣。
    func foldMarkerRects(in rect: NSRect? = nil) -> [(rect: NSRect, fold: Fold)] {
        let length = textStorage?.length ?? 0
        var candidates = folds[...]
        if let rect, let layout = layoutManager, let container = textContainer {
            let glyphs = layout.glyphRange(forBoundingRect: rect.offsetBy(dx: 0, dy: -textContainerOrigin.y), in: container)
            let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let first = max(0, firstFoldIndex(endingAfter: chars.location) - 1)
            let end = min(folds.count, firstFoldIndex(endingAfter: NSMaxRange(chars)) + 1)
            candidates = first < end ? folds[first..<end] : []
        }
        return candidates.filter { NSMaxRange($0.hidden) <= length }.map { fold in
            let rect = foldFragmentRect(fold)
            let pad = paddingByLocation[fold.hidden.location] ?? 0
            return (NSRect(x: 0, y: rect.minY + pad + textContainerOrigin.y, width: bounds.width, height: Theme.lineHeight), fold)
        }
    }

    /// 游標或選取範圍落在其中的摺疊區。
    func fold(holdingSelectionAmong candidates: [Fold]) -> Fold? {
        guard !candidates.isEmpty else { return nil }
        let selection = selectedRange()
        return candidates.first { fold in
            guard selection.length == 0 else { return NSIntersectionRange(selection, fold.hidden) == selection }
            return selection.location >= fold.hidden.location && selection.location < NSMaxRange(fold.hidden)
        }
    }

    /// 游標停在文件結尾，而最後一段被摺疊時，回傳那一段。
    func tailFoldAtCaret() -> Fold? {
        let selection = selectedRange()
        let length = textStorage?.length ?? 0
        guard selection.length == 0, selection.location == length, let last = folds.last, NSMaxRange(last.hidden) == length else { return nil }
        return last
    }

    /// 這個文字框正在輸入，而且游標落在 fold 中間。貼上整份文件後游標停在結尾，不算正在編輯最後一段。
    func isEditing(within candidate: Fold) -> Bool {
        window?.firstResponder === self && fold(holdingSelectionAmong: [candidate]) != nil
    }

    func fold(at point: NSPoint) -> Fold? {
        foldMarkerRects(in: NSRect(origin: point, size: NSSize(width: 1, height: 1))).first { $0.rect.contains(point) }?.fold
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard !folds.isEmpty else { return 0 }
        var hiddenProperties = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        var changed = false
        for i in hiddenProperties.indices where isHidden(characterIndexes[i]) && !hiddenProperties[i].contains(.controlCharacter) {
            hiddenProperties[i] = .null
            changed = true
        }
        guard changed else { return 0 }
        hiddenProperties.withUnsafeBufferPointer {
            layoutManager.setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: characterIndexes,
                                    font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard !folds.isEmpty else { return false }
        let location = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        guard let fold = fold(containing: location) else { return false }
        let rect = lineFragmentRect.pointee
        let style = textStorage?.attribute(.paragraphStyle, at: fold.hidden.location, effectiveRange: nil) as? NSParagraphStyle
        // 摺疊區只排成一列，但這一列不一定從摺疊區開頭排起（見 foldFragmentRect），所以補白不看起點。
        let spacing = style?.paragraphSpacingBefore ?? 0
        lineFragmentRect.pointee.size.height = Theme.lineHeight + spacing
        lineFragmentUsedRect.pointee = NSRect(x: rect.minX, y: rect.minY + spacing, width: 0, height: Theme.lineHeight)
        return true
    }

    /// 摺疊區內的換行不斷行，只有最後一個換行保留，整段就排成一行。
    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let fold = fold(containing: charIndex), charIndex != NSMaxRange(fold.hidden) - 1 else { return action }
        return .zeroAdvancement
    }

    /// 打字時讓摺疊範圍跟著平移。編輯落在摺疊範圍內就展開那一段，避免改到看不見的文字。
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let start = editedRange.location
        let oldEnd = start + editedRange.length - delta
        let oldLength = textStorage.length - delta
        if start == 0 && oldEnd == oldLength { onTextReplaced?() }
        guard !folds.isEmpty else { return }
        var kept: [Fold] = []
        var dropped: [Fold] = []
        for var fold in folds {
            let end = NSMaxRange(fold.hidden)
            if start == end && end == oldLength {
                // 在文件結尾打字，會接在摺疊起來的最後一行後面
                dropped.append(fold)
            } else if oldEnd <= fold.hidden.location {
                fold.hidden.location += delta
                kept.append(fold)
            } else if start >= end {
                kept.append(fold)
            } else if start > fold.hidden.location || oldEnd < end {
                dropped.append(fold)
            }
        }
        folds = kept
        // 整段被取代的摺疊區（全選貼上、對調、拖放）直接丟掉，只有編輯落在摺疊區內才算使用者展開。
        guard !dropped.isEmpty else { return }
        // 被展開的摺疊區在編輯後的範圍：從最前面那段的開頭，到最後那段的結尾加上這次的長度變化。
        let spanStart = dropped.map(\.hidden.location).min()!
        let spanEnd = dropped.map { NSMaxRange($0.hidden) }.max()! + delta
        DispatchQueue.main.async { [self] in
            if let layout = layoutManager {
                let span = NSIntersectionRange(NSRange(location: spanStart, length: max(0, spanEnd - spanStart)),
                                               NSRange(location: 0, length: textStorage.length))
                layout.invalidateGlyphs(forCharacterRange: span, changeInLength: 0, actualCharacterRange: nil)
                layout.invalidateLayout(forCharacterRange: span, actualCharacterRange: nil)
            }
            dropped.forEach { onRevealFold?($0) }
        }
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
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.lineNumber]
        for (box, fold) in foldMarkerRects(in: rect) where box.intersects(rect) {
            Theme.hunkLine.setFill()
            box.fill()
            let label = "⋯ 未變動 \(fold.lineCount) 行" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: textContainerOrigin.x + textContainer!.lineFragmentPadding, y: box.minY + (box.height - size.height) / 2),
                       withAttributes: attributes)
        }
    }

    /// 對齊用的補白區塊，座標是文字框本身的座標系。
    func fillerRects() -> [NSRect] {
        guard let layout = layoutManager, let container = textContainer else { return [] }
        let origin = textContainerOrigin.y
        let length = text.length
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
        let length = text.length
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
        let chars = text.lineRange(for: line)
        if chars.length == 0 { return layout.extraLineFragmentRect }
        if let fold = fold(containing: chars.location) { return foldFragmentRect(fold) }
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
