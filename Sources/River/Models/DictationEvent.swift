import Foundation

/// What became of a dictation River couldn't type as soon as it ended (planning 0004). The
/// session sends each while River is still `.processing`, so the panel can show it before it
/// leaves.
enum DictationEvent: Equatable {
    /// The recording waits for the model to download or get ready.
    case waitingForModel
    /// The model failed to load. The recording is kept, and the next load that succeeds
    /// transcribes it.
    case recordingKept
    /// The app in front at the release left the front before or while River typed: River
    /// stopped typing and holds the text as the last transcript (planning 0039).
    case textHeld
}
