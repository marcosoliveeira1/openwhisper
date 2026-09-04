import Foundation

enum FailureReason: Error, Equatable {
    case permissionDenied
    case recognitionUnavailable
    case engineError(String)
}

protocol DictationService: AnyObject {
    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) async

    func start() async throws
    func finish() async -> String?
    func cancel() async
}
