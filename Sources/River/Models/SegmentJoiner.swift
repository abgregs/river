import Foundation

/// Joins decoded segments into one transcript (0025 review §3). Every segment is decoded as
/// if it were a whole utterance, so Whisper ends each with a period and capitalizes the next:
/// "the best option is. To move the launch". Three measures, all pure:
///
/// - **Overlap decode.** A segment is decoded with the end of the previous one in front of it.
///   The longest run of the joint output that matches the tail of the transcript (at least two
///   words) is the overlap: it is dropped, and the punctuation the joint decode put after it
///   replaces the punctuation held at the join. No match means no safe way to strip the
///   overlap; the caller decodes the segment cold instead, so a miss can never repeat words.
/// - **Held punctuation.** A segment's trailing punctuation is held back until the next
///   segment says what the join is.
/// - **Two join rules.** A transcript ending in a function word ("is", "to", "the") can't be
///   at a sentence end, so a terminal mark there is dropped and the next word lowercased; a
///   segment opening with a conjunction ("because", "which") after a terminal mark turns it
///   into a comma.
///
/// Measured on the think-aloud clip: every mid-sentence break healed except one defensible
/// sentence boundary, and zero word errors on the long clip with both models.
struct SegmentJoiner {
    /// Segment texts with their held punctuation removed; the join punctuation is appended
    /// to the previous body when the next segment arrives.
    private(set) var bodies: [String] = []
    /// The trailing punctuation of the last segment, not yet confirmed by a join.
    private(set) var held = ""

    var isEmpty: Bool { bodies.isEmpty }
    var text: String { bodies.isEmpty ? "" : bodies.joined(separator: " ") + held }

    /// How many transcript words the overlap is aligned against.
    static let alignmentWindow = 8

    /// Appends a segment decoded on its own.
    mutating func appendCold(_ decoded: String) {
        add(Self.words(decoded), joinPunctuation: held)
    }

    /// Appends a segment decoded with the previous segment's end in front of it. Returns
    /// `false`, changing nothing, when the overlap can't be found in the joint text.
    mutating func appendOverlapped(_ joint: String) -> Bool {
        let jointWords = Self.words(joint)
        guard !bodies.isEmpty else {
            add(jointWords, joinPunctuation: held)
            return true
        }
        let tail = bodies.joined(separator: " ").split(separator: " ").suffix(Self.alignmentWindow).map { Self.normalized(String($0)) }
        let shortest = min(2, tail.count)
        guard shortest > 0 else { return false }
        var match: (start: Int, length: Int)?
        for length in stride(from: tail.count, through: shortest, by: -1) where length <= jointWords.count {
            let target = Array(tail.suffix(length))
            for start in 0...(jointWords.count - length)
            where jointWords[start..<(start + length)].map(Self.normalized) == target {
                match = (start, length)
                break
            }
            if match != nil { break }
        }
        guard let match else { return false }
        let joinPunctuation = Self.splitTrailingPunctuation(jointWords[match.start + match.length - 1]).punctuation
        add(Array(jointWords[(match.start + match.length)...]), joinPunctuation: joinPunctuation)
        return true
    }

    private mutating func add(_ incoming: [String], joinPunctuation: String) {
        var words = incoming
        var punctuation = joinPunctuation
        if let last = bodies.last {
            let tailWord = last.split(separator: " ").last.map { Self.normalized(String($0)) } ?? ""
            let nextWord = words.first.map(Self.normalized) ?? ""
            if Self.functionWords.contains(tailWord) {
                if Self.isTerminal(punctuation) { punctuation = "" }
                words = Self.lowercasingFirst(words)
            } else if Self.conjunctions.contains(nextWord), Self.isTerminal(punctuation) {
                punctuation = ","
                words = Self.lowercasingFirst(words)
            }
        }
        let (body, trailing) = Self.splitTrailingPunctuation(words.joined(separator: " "))
        guard !body.isEmpty else {
            // Nothing new was said: the join punctuation is still the transcript's ending.
            if !bodies.isEmpty { held = trailing.isEmpty ? punctuation : trailing }
            return
        }
        if !bodies.isEmpty { bodies[bodies.count - 1] += punctuation }
        bodies.append(body)
        held = trailing
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func splitTrailingPunctuation(_ text: String) -> (body: String, punctuation: String) {
        var body = Substring(text)
        var punctuation = ""
        while let last = body.last, last.isPunctuation {
            punctuation = String(last) + punctuation
            body = body.dropLast()
        }
        return (String(body), punctuation)
    }

    static func isTerminal(_ punctuation: String) -> Bool {
        punctuation.contains(".") || punctuation.contains("!") || punctuation.contains("?")
    }

    private static func lowercasingFirst(_ words: [String]) -> [String] {
        guard let first = words.first, !keepCase.contains(normalized(first)) else { return words }
        return [first.prefix(1).lowercased() + first.dropFirst()] + words.dropFirst()
    }

    // Words that can't end a sentence: a join after one is mid-sentence.
    static let functionWords: Set<String> = [
        "a", "an", "the", "to", "of", "in", "on", "at", "for", "with", "about", "from", "by", "is", "are",
        "was", "were", "be", "been", "and", "or", "but", "that", "this", "as", "if", "so", "than", "into",
        "over", "under", "my", "your", "our", "their", "his", "her", "its", "very", "not", "no", "i", "we",
        "they", "he", "she", "it", "you", "will", "would", "could", "should", "can", "has", "have", "had",
        "do", "does", "did", "which", "who", "what", "where", "when", "how", "because", "while",
    ]
    // Words that open a continuation rather than a new sentence.
    static let conjunctions: Set<String> = [
        "because", "but", "and", "which", "so", "or", "then", "that", "who", "where", "when", "while",
        "although", "though", "if", "unless", "since", "nor", "yet", "whereas",
    ]
    // Capitalized wherever they fall.
    static let keepCase: Set<String> = [
        "i", "im", "id", "ill", "ive", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
}
