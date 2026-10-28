import Foundation

/// Simplified to Traditional Chinese as used in Taiwan, matching OpenCC's
/// `s2tw`: the longest STPhrases match at each position, else STCharacters,
/// then TWVariants per character. Characters only, no vocabulary swaps
/// (`s2twp` would also turn 參數 into 引數). Other text passes through.
/// Dictionaries: OpenCC (Apache 2.0), `Resources/OpenCC`.
public final class ChineseConverter: Sendable {
    public static let shared = ChineseConverter()

    private let phrases: [String: String]
    private let characters: [Character: String]
    private let variants: [Character: String]
    private let longestPhrase: Int

    init(bundle: Bundle = .module) {
        func load(_ name: String) -> [(key: String, value: String)] {
            guard let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "OpenCC"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(whereSeparator: \.isNewline).compactMap { line in
                let fields = line.split(separator: "\t", maxSplits: 1)
                guard fields.count == 2, let first = fields[1].split(separator: " ").first else { return nil }
                return (String(fields[0]), String(first))
            }
        }
        func byCharacter(_ entries: [(key: String, value: String)]) -> [Character: String] {
            Dictionary(entries.compactMap { $0.key.count == 1 ? ($0.key.first!, $0.value) : nil },
                       uniquingKeysWith: { first, _ in first })
        }
        let phraseEntries = load("STPhrases")
        phrases = Dictionary(phraseEntries, uniquingKeysWith: { first, _ in first })
        longestPhrase = phraseEntries.map(\.key.count).max() ?? 1
        characters = byCharacter(load("STCharacters"))
        variants = byCharacter(load("TWVariants"))
    }

    public func toTraditionalTaiwan(_ text: String) -> String {
        let input = Array(text)
        var converted = ""
        var index = 0
        next: while index < input.count {
            var length = min(longestPhrase, input.count - index)
            while length > 1 {
                if let phrase = phrases[String(input[index..<index + length])] {
                    converted += phrase
                    index += length
                    continue next
                }
                length -= 1
            }
            let character = input[index]
            converted += phrases[String(character)] ?? characters[character] ?? String(character)
            index += 1
        }
        return String(converted.flatMap { variants[$0] ?? String($0) })
    }
}
