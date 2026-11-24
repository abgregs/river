import Foundation

/// A cycle error as the status in the mark's place: a headline, a short detail on the same line,
/// and the mark in its tile (planning 0018, shown as a status since 2026-11-24). Distinct from the
/// lingering menu-row `errorMessage`: this leaves after `statusHoldSeconds`. Fixed copy per error
/// *kind*, so it carries no user content and needs no redaction (the underlying framework message,
/// which may name a home path, stays on the redacted `errorMessage` path only).
struct ErrorStatus: Equatable {
    enum Mark: Equatable {
        /// Couldn't load the model's mark: the akane ring round the exclamation mark.
        case failed
        /// A permission River needs is off: the lock.
        case locked
    }

    let headline: String
    let detail: String
    let mark: Mark
}

/// Pure mapping from `RiverError` kind → status, exactly like `MenuBarPresentation.visual`.
/// Structures the *presentation*, not the error: the typed `RiverError` taxonomy is unchanged
/// (planning 0018). Every case maps, so a new error stage is a compile error here, not a silently
/// missing status.
enum ErrorStatusPresentation {
    static func status(for error: RiverError) -> ErrorStatus {
        switch error {
        case .audioCapture(let underlying):
            // The microphone stopped part-way (the audio device changed and the engine could not
            // recover): "check your microphone" would misdirect, since one was there. Say what
            // happened and what the user still has.
            if let captureError = underlying as? AudioCaptureError,
               case .captureIncomplete = captureError {
                return ErrorStatus(headline: "Recording cut short", detail: "Typed what it heard", mark: .failed)
            }
            return ErrorStatus(headline: "Couldn’t capture audio", detail: "Check your microphone", mark: .failed)
        case .permission(let capability):
            // Nothing failed: the recording was declined before it started (planning 0012 AC5).
            // The detail points at the fix, since the user is holding a key expecting to dictate
            // and nothing happened. Permissions are a section of the Settings window (0036).
            return ErrorStatus(headline: "\(capability) access needed", detail: "Grant it in Settings", mark: .locked)
        case .transcription:
            return ErrorStatus(headline: "Couldn’t transcribe", detail: "Try speaking louder", mark: .failed)
        case .textInsertion:
            return ErrorStatus(headline: "Couldn’t paste", detail: "Click into a text field", mark: .failed)
        }
    }
}
