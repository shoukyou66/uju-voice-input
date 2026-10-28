import Foundation
// The only file in KVoiceKit that imports FoundationModels.
import FoundationModels

/// Why Apple Intelligence cannot run right now.
public enum AppleIntelligenceAvailability: Sendable, Hashable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case unknown

    public var isAvailable: Bool { self == .available }

    public var message: String {
        switch self {
        case .available: "Apple Intelligence 已就緒。"
        case .deviceNotEligible: "這部裝置不支援 Apple Intelligence。"
        case .notEnabled: "請到「設定」開啟 Apple Intelligence，才能用它來整理文字。"
        case .modelNotReady: "Apple Intelligence 仍在下載中，請稍後再試。"
        case .unknown: "Apple Intelligence 目前無法使用。"
        }
    }
}

/// On-device formatting with the system language model. No key, no network.
public struct AppleIntelligenceFormatter: TextFormatter {
    public init() {}

    public static var availability: AppleIntelligenceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unknown
            }
        }
    }

    public func format(_ request: FormatRequest) async throws -> String {
        let availability = Self.availability
        guard availability.isAvailable else {
            throw ProviderError.unavailable(availability.message)
        }
        let prompt = PromptComposer.compose(request)
        // One session per request: formatting is stateless, and a shared
        // transcript would only use up the context window.
        let session = LanguageModelSession(instructions: prompt.system)
        do {
            let response = try await session.respond(
                to: prompt.user,
                options: GenerationOptions(samplingMode: .greedy)
            )
            let text = PromptComposer.cleanedOutput(response.content)
            guard !text.isEmpty else { throw ProviderError.emptyResponse }
            return text
        } catch let error as ProviderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                throw ProviderError.refused
            case .exceededContextWindowSize:
                throw ProviderError.unavailable("文字太長，Apple Intelligence 無法處理。請改用雲端供應商。")
            case .unsupportedLanguageOrLocale:
                throw ProviderError.unavailable("Apple Intelligence 目前還不支援這個語言。")
            case .assetsUnavailable:
                throw ProviderError.unavailable(AppleIntelligenceAvailability.modelNotReady.message)
            case .rateLimited, .concurrentRequests:
                throw ProviderError.rateLimited
            default:
                throw ProviderError.unavailable("Apple Intelligence 無法整理這段文字。")
            }
        }
    }
}
