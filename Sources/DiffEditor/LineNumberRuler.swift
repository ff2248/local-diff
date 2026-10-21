import AppKit
import DiffCore

final class LineNumberRuler: NSRulerView {
    init(textView: DiffTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 36
    }

    required init(coder: NSCoder) { fatalError() }

    /// 依行號位數與目前字級的數字寬度調整欄寬。
    func updateThickness(lineCount: Int, fontSize: CGFloat) {
        let digits = CGFloat(String(max(lineCount, 1)).count)
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: Self.font(fontSize)]).width
        let thickness = max(36, (digits * digitWidth).rounded(.up) + 16)
        if ruleThickness != thickness { ruleThickness = thickness }
    }

    static func font(_ fontSize: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: fontSize - 2, weight: .regular)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? DiffTextView else { return }
        Theme.background.setFill()
        band(rect).intersection(bounds).fill()
        Theme.filler.setFill()
        for filler in textView.fillerRects() { band(convert(filler, from: textView)).fill() }
        for (box, kind) in textView.highlightedLineRects() {
            numberColor(for: kind, side: textView.side).setFill()
            band(convert(box, from: textView)).fill()
        }
        Theme.hunkNumber.setFill()
        for marker in textView.foldMarkerRects(in: textView.visibleRect) { band(convert(marker.rect, from: textView)).fill() }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font(textView.style.fontSize),
            .foregroundColor: Theme.lineNumber,
        ]
        for (number, y) in textView.lineNumberPositions(in: textView.visibleRect) {
            let label = String(number) as NSString
            let size = label.size(withAttributes: attributes)
            let point = convert(NSPoint(x: 0, y: y), from: textView)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: point.y + (textView.style.lineHeight - size.height) / 2),
                       withAttributes: attributes)
        }
    }

    private func band(_ rect: NSRect) -> NSRect {
        NSRect(x: 0, y: rect.minY, width: ruleThickness, height: rect.height)
    }

    private func numberColor(for kind: HighlightKind, side: DiffTextView.Side) -> NSColor {
        switch kind {
        case .lineDeleted: Theme.deletedNumber
        case .lineInserted: Theme.insertedNumber
        case .lineModified: side == .left ? Theme.deletedNumber : Theme.insertedNumber
        default: Theme.movedNumber
        }
    }
}
