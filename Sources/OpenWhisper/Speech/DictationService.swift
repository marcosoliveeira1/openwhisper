import Foundation

enum FailureReason: Error, Equatable {
    case permissionDenied
    case recognitionUnavailable
    case engineError(String)
    case noSpeech
}

protocol DictationService: AnyObject, Sendable {
    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) async

    func start() async throws
    func finish() async -> String?
    func cancel() async
}

protocol AudioLevelProviding: AnyObject {
    func setLevelHandler(_ handler: @escaping @Sendable (Double) -> Void) async
}
