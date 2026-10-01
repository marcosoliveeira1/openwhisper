#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple Intelligence on-device cleanup. macOS 26+ only.
///
/// Each call runs on a FRESH session: the session API is conversational, and
/// reusing one across independent cleanups lets earlier turns bleed into
/// later ones (echoes, continuations). Stateless per call = no bleed.
@available(macOS 26, *)
final class FoundationModelsPolisher: TextPolisher, Sendable {
    init() {}

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "Limpeza com IA indisponível neste Mac (requer Apple Intelligence)"
        case .unavailable(.appleIntelligenceNotEnabled):
            "Ative o Apple Intelligence em Ajustes para usar a limpeza com IA"
        case .unavailable(.modelNotReady):
            "Modelo de IA ainda baixando — tente novamente em instantes"
        case .unavailable:
            "Limpeza com IA indisponível no momento"
        }
    }

    func polish(_ text: String) async throws -> String {
        guard isAvailable else {
            throw PolishError.unavailable(availabilityMessage ?? "Limpeza com IA indisponível")
        }
        do {
            let session = LanguageModelSession(instructions: PolishPrompt.instructions)
            let response = try await session.respond(to: PolishPrompt.prompt(for: text))
            let cleaned = PolishPrompt.clean(response.content)
            guard !cleaned.isEmpty else {
                throw PolishError.failed("resposta vazia do modelo")
            }
            guard PolishPrompt.isPlausible(cleaned, for: text) else {
                throw PolishError.failed("resposta inconsistente do modelo")
            }
            return cleaned
        } catch let error as PolishError {
            throw error
        } catch {
            throw PolishError.failed(error.localizedDescription)
        }
    }
}
#endif
