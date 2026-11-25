import Foundation
import Testing
@testable import River

@Suite("ErrorStatusPresentation")
struct ErrorStatusPresentationTests {
    // The error-kind → status mapping is a pure function covering every RiverError case
    // (planning 0018 AC3). A missing case is a compile error (the switch is exhaustive); empty
    // copy would ship a blank status.
    private static let dummy = NSError(domain: "x", code: 1)

    @Test("every RiverError kind maps to a headline and a detail")
    func everyCaseHasHeadlineAndDetail() {
        let errors: [RiverError] = [
            .audioCapture(underlying: Self.dummy),
            .transcription(underlying: Self.dummy),
            .textInsertion(underlying: Self.dummy),
            .permission(capability: "Accessibility"),
        ]
        for error in errors {
            let status = ErrorStatusPresentation.status(for: error)
            #expect(!status.headline.isEmpty)
            #expect(!status.detail.isEmpty)
        }
    }

    @Test("a failure shows Couldn't load the model's ring; a permission refused shows the lock")
    func marks() {
        // Nothing failed when a permission is off: the recording was declined before it
        // started, so it takes the lock, not the failure's akane ring (maintainer, 2026-11-24).
        #expect(ErrorStatusPresentation.status(for: .transcription(underlying: Self.dummy)).mark == .failed)
        #expect(ErrorStatusPresentation.status(for: .textInsertion(underlying: Self.dummy)).mark == .failed)
        #expect(ErrorStatusPresentation.status(for: .audioCapture(underlying: Self.dummy)).mark == .failed)
        #expect(ErrorStatusPresentation.status(for: .permission(capability: "Microphone")).mark == .locked)
    }

    @Test("a permission refused names the permission and sends the user to Settings")
    func permissionNamesTheFix() {
        // The Permissions menu item became a section of the Settings window (planning 0036).
        let status = ErrorStatusPresentation.status(for: .permission(capability: "Input Monitoring"))
        #expect(status.headline == "Input Monitoring access needed")
        #expect(status.detail == "Grant it in Settings")
    }

    @Test("an incomplete capture gets its own headline, not the check-your-microphone detail")
    func incompleteCaptureHasOwnStatus() {
        // The microphone was there and stopped part-way (planning 0032). Telling the user to
        // check it would misdirect; the status says what happened and that the words heard
        // were typed.
        let cut = ErrorStatusPresentation.status(for: .audioCapture(
            underlying: AudioCaptureError.captureIncomplete(capturedSeconds: 1.5, recordingSeconds: 14)))
        let generic = ErrorStatusPresentation.status(for: .audioCapture(underlying: AudioCaptureError.noAudioCaptured))
        #expect(cut.headline != generic.headline)
        #expect(cut.detail.contains("Typed"))
    }

    @Test("the three stages produce distinct headlines")
    func distinctHeadlinesPerKind() {
        // A copy-paste slip that mapped two kinds to the same headline would make the status
        // diagnostically useless: the point of 0018 is an actionable, kind-specific message.
        let audio = ErrorStatusPresentation.status(for: .audioCapture(underlying: Self.dummy)).headline
        let transcribe = ErrorStatusPresentation.status(for: .transcription(underlying: Self.dummy)).headline
        let paste = ErrorStatusPresentation.status(for: .textInsertion(underlying: Self.dummy)).headline
        #expect(Set([audio, transcribe, paste]).count == 3)
    }

    @Test("the status carries no user content from the underlying error")
    func statusCarriesNoUserContent() {
        // Fixed copy per kind, so a home path inside the framework error can't ride onto it
        // (that message stays on the redacted errorMessage path only).
        let underlying = NSError(domain: "WhisperKit", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "failed at /Users/alice/secret.bin"])
        let status = ErrorStatusPresentation.status(for: .transcription(underlying: underlying))
        #expect(!status.headline.contains("/Users/alice"))
        #expect(!status.detail.contains("/Users/alice"))
    }
}
