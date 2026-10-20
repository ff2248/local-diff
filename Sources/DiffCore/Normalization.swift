import Foundation

public struct CompareOptions: Equatable, Sendable {
    public var ignoreWhitespace: Bool
    public var ignoreBlankLines: Bool
    public var ignoreCase: Bool
    public var ignoreWidth: Bool

    public init(ignoreWhitespace: Bool = false, ignoreBlankLines: Bool = false,
                ignoreCase: Bool = false, ignoreWidth: Bool = false) {
        self.ignoreWhitespace = ignoreWhitespace
        self.ignoreBlankLines = ignoreBlankLines
        self.ignoreCase = ignoreCase
        self.ignoreWidth = ignoreWidth
    }
}

public struct Token: Equatable, Sendable {
    public let range: NSRange
    public let key: String
}

public func normalizedKey(_ text: String, _ options: CompareOptions) -> String {
    var result = ""
    for ch in text {
        let n = normalize(ch, options)
        if options.ignoreWhitespace && n.allSatisfy(\.isWhitespace) { continue }
        result += n
    }
    return result
}

public func tokenize(_ text: String, _ options: CompareOptions) -> [Token] {
    enum Kind { case word, space, single }
    var tokens: [Token] = []
    var start = 0
    var offset = 0
    var key = ""
    var kind: Kind?

    func flush() {
        guard let k = kind else { return }
        if !(k == .space && options.ignoreWhitespace) {
            tokens.append(Token(range: NSRange(location: start, length: offset - start), key: key))
        }
        kind = nil
        key = ""
    }

    for ch in text {
        let n = normalize(ch, options)
        let c = n.first ?? ch
        let k: Kind
        if c.isWhitespace {
            k = .space
        } else if (c.isLetter || c.isNumber || c == "_") && !c.isIdeographic {
            k = .word
        } else {
            k = .single
        }
        if k == .single || k != kind {
            flush()
            start = offset
            kind = k
        }
        key += n
        offset += ch.utf16.count
    }
    flush()
    return tokens
}

private func normalize(_ ch: Character, _ options: CompareOptions) -> String {
    var s = String(ch)
    if options.ignoreWidth {
        s = String(String.UnicodeScalarView(s.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0xFF01...0xFF5E: Unicode.Scalar(scalar.value - 0xFEE0)!
            case 0x3000: " "
            default: scalar
            }
        }))
    }
    if options.ignoreCase { s = s.lowercased() }
    return s
}
