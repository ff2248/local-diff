import AppKit
import DiffCore

final class LineNumberRuler: NSRulerView {
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: Theme.lineNumber,
    ]

    init(textView: DiffTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 36
    }

    required init(coder: NSCoder) { fatalError() }

    func updateThickness(lineCount: Int) {
        let digits = String(max(lineCount, 1)).count
        let thickness = max(36, CGFloat(digits) * 7 + 16)
        if ruleThickness != thickness { ruleThickness = thickness }
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
        for (number, y) in textView.lineNumberPositions(in: textView.visibleRect) {
            let label = String(number) as NSString
            let size = label.size(withAttributes: attributes)
            let point = convert(NSPoint(x: 0, y: y), from: textView)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: point.y + (Theme.lineHeight - size.height) / 2),
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
