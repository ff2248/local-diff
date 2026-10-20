public struct TextStats: Equatable, Sendable {
    public let characters: Int
    public let cjkCharacters: Int
    public let lines: Int
    public let estimatedTokens: Int
}

extension TextStats {
    public init(text: String) {
        var characters = 0
        var cjk = 0
        var otherNonWhitespace = 0
        var newlines = 0
        for ch in text {
            if ch.isNewline {
                newlines += 1
                continue
            }
            characters += 1
            if ch.isIdeographic {
                cjk += 1
            } else if !ch.isWhitespace {
                otherNonWhitespace += 1
            }
        }
        var lines = 0
        if !text.isEmpty {
            lines = newlines + 1
            if text.last!.isNewline { lines -= 1 }
        }
        self.init(
            characters: characters,
            cjkCharacters: cjk,
            lines: lines,
            estimatedTokens: cjk + (otherNonWhitespace + 3) / 4
        )
    }
}

extension Character {
    var isIdeographic: Bool { unicodeScalars.first!.properties.isIdeographic }
}
