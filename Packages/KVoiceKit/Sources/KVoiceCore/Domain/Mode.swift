import Foundation

/// A dictation mode: what happens to a transcript after speech recognition.
///
/// A `.plainDictation` mode inserts the transcript as spoken (no AI, works
/// offline). An `.aiFormat` mode sends the transcript to an AI provider with
/// the mode's `instructions`.
public struct Mode: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        /// The transcript as recognised, no AI step.
        case plainDictation
        /// The transcript reformatted by an AI provider.
        case aiFormat
    }

    public var id: UUID
    public var name: String
    /// An SF Symbol name.
    public var icon: String
    /// Instructions for the AI step; ignored for `.plainDictation`.
    public var instructions: String
    public var kind: Kind
    /// Spoken language: `nil` means automatic detection, otherwise a BCP-47
    /// tag such as "en-US" or "de".
    public var language: String?
    /// Ask for English output: the Whisper engine translates while it
    /// transcribes, and the AI step is told to write English.
    public var translateToEnglish: Bool
    /// Use this provider instead of the default one for the AI step.
    public var providerOverride: ProviderConfiguration?
    /// Use this engine instead of the default one for transcription.
    public var engineOverride: TranscriptionEngineSelection?
    /// True for the modes KVoice ships with. Built-ins can be edited but are
    /// restored by "reset", and their identifiers are stable.
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "text.bubble",
        instructions: String = "",
        kind: Kind = .aiFormat,
        language: String? = nil,
        translateToEnglish: Bool = false,
        providerOverride: ProviderConfiguration? = nil,
        engineOverride: TranscriptionEngineSelection? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.instructions = instructions
        self.kind = kind
        self.language = language
        self.translateToEnglish = translateToEnglish
        self.providerOverride = providerOverride
        self.engineOverride = engineOverride
        self.isBuiltIn = isBuiltIn
    }

    /// Whether the pipeline runs an AI step for this mode.
    public var usesAI: Bool { kind == .aiFormat }
}

// MARK: - Built-in modes

extension Mode {
    /// Stable identifiers so the keyboard and the app agree on built-ins
    /// across launches and resets.
    public enum BuiltInID {
        public static let dictation = UUID(uuidString: "6B7C0001-0000-4000-8000-000000000001")!
        public static let cleanUp = UUID(uuidString: "6B7C0001-0000-4000-8000-000000000002")!
        public static let message = UUID(uuidString: "6B7C0001-0000-4000-8000-000000000003")!
        public static let email = UUID(uuidString: "6B7C0001-0000-4000-8000-000000000004")!
        public static let notes = UUID(uuidString: "6B7C0001-0000-4000-8000-000000000005")!
        public static let summary = UUID(uuidString: "6B7C0001-0000-4000-8000-000000000006")!
        public static let translateToEnglish = UUID(uuidString: "6B7C0001-0000-4000-8000-000000000007")!
    }

    public static let dictation = Mode(
        id: BuiltInID.dictation,
        name: "Smart",
        icon: "sparkles",
        instructions: "",
        kind: .plainDictation,
        isBuiltIn: true
    )

    public static let cleanUp = Mode(
        id: BuiltInID.cleanUp,
        name: "整理贅詞",
        icon: "sparkles",
        instructions: """
        Clean up the dictated text. Remove filler words, stutters, false starts and \
        accidental repetitions; where the speaker restated something, keep only the \
        final version. Fix punctuation, capitalization, grammar and sentence \
        boundaries, and correct clearly misheard words when context makes the \
        intended word obvious. Keep the speaker's wording, tone, and meaning. Leave \
        names, numbers, URLs, code and technical terms untouched. Do not add, \
        answer, summarize, or continue anything.
        """,
        isBuiltIn: true
    )

    public static let message = Mode(
        id: BuiltInID.message,
        name: "口語聊天",
        icon: "message",
        instructions: """
        把這段聽寫改成自然的聊天訊息：保留原意和說話者的語氣，輕鬆親切，句子短一點，        可以分成幾句。說話者沒說的問候語或署名不要加，不要用 Markdown，        不要回答、延伸或補充內容。用台灣繁體中文和台灣用語；英文專有名詞保持原樣。
        """,
        providerOverride: .geminiFormatting,
        isBuiltIn: true
    )

    public static let email = Mode(
        id: BuiltInID.email,
        name: "電子郵件",
        icon: "envelope",
        instructions: """
        Turn the dictated text into a well-written email body. Add a greeting and a \
        sign-off line only if the speaker named the recipient or themselves; never \
        invent names. Use short paragraphs, a clear and polite tone, and correct \
        grammar and punctuation. Keep every fact the speaker gave and add none. \
        Do not write a subject line. No Markdown.
        """,
        isBuiltIn: true
    )

    public static let notes = Mode(
        id: BuiltInID.notes,
        name: "筆記",
        icon: "list.bullet",
        instructions: """
        Turn the dictated text into concise notes: a bulleted list using "- " with \
        one idea per bullet, grouped in the order spoken. Keep names, numbers, dates \
        and action items exactly. Drop filler and repetition. Do not add a title or \
        anything that was not said.
        """,
        isBuiltIn: true
    )

    public static let summary = Mode(
        id: BuiltInID.summary,
        name: "專注摘要",
        icon: "list.bullet",
        instructions: """
        把這段聽寫整理成重點：用「- 」條列，每條一個重點，照說話的順序；        人名、數字、日期和待辦事項完整保留，刪掉重複和贅詞，        不加入沒說過的內容或意見。用台灣繁體中文和台灣用語；英文專有名詞保持原樣。
        """,
        providerOverride: .geminiFormatting,
        isBuiltIn: true
    )

    public static let translateToEnglish = Mode(
        id: BuiltInID.translateToEnglish,
        name: "翻成英文",
        icon: "globe",
        instructions: """
        Translate the dictated text into fluent, natural English. Remove filler \
        words and false starts before translating, preserve the tone and meaning, \
        and keep names, URLs, code and numbers unchanged. If the text is already \
        English, return it cleaned up but untranslated.
        """,
        translateToEnglish: true,
        isBuiltIn: true
    )

    /// The three personalities shown on the keyboard, in display order. The
    /// other modes above stay defined for reference but are not offered.
    public static let builtIns: [Mode] = [.dictation, .message, .summary]
}
