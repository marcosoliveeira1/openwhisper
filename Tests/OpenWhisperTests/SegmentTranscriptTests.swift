import Foundation
import Testing

@testable import OpenWhisper

@Suite struct SegmentTranscriptTests {
    @Test func partialWithoutPrefixReturnsPartialOnly() {
        var transcript = SegmentTranscript()
        #expect(transcript.combined("olá") == "olá")
        #expect(transcript.combined("") == "")
    }

    @Test func partialWithPrefixIsConcatenated() {
        var transcript = SegmentTranscript()
        transcript.finalize(with: "primeira frase")
        #expect(transcript.combined("segunda") == "primeira frase segunda")
    }

    @Test func finalizeMergesCurrentIntoPrefix() {
        var transcript = SegmentTranscript()
        transcript.finalize(with: "parte um")
        transcript.finalize(with: "parte dois")
        #expect(transcript.finalizedPrefix == "parte um parte dois")
    }

    @Test func finalizeWithEmptyKeepsPrefix() {
        var transcript = SegmentTranscript()
        transcript.finalize(with: "algo dito")
        transcript.finalize(with: "")
        #expect(transcript.finalizedPrefix == "algo dito")
    }

    @Test func resetClearsPrefix() {
        var transcript = SegmentTranscript()
        transcript.finalize(with: "velho")
        transcript.reset()
        #expect(transcript.finalizedPrefix == "")
    }
}
