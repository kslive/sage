import ChatService
import CoreKit
import Foundation
import GitService
import MarkdownService
import ModelService
import SpeechService
import VaultService

/// Контейнер сервисов приложения (composition root).
struct AppComposition {
    let models: ModelManaging
    let vault: VaultServicing
    let markdown: MarkdownRendering
    let ai: AICoordinating
    let speech: Transcribing
    let chatStore: ChatStoring
    let git: GitServicing

    static func make(ai: AICoordinating, vault: VaultServicing) -> AppComposition {
        AppComposition(
            models: ModelService.shared,
            vault: vault,
            markdown: MarkdownService(),
            ai: ai,
            speech: SpeechService(),
            chatStore: ChatStore(),
            git: GitService()
        )
    }
}
