import Foundation

/// What became of a dictation that ended before the model was ready (planning 0004). The
/// session sends each while River is still `.processing`, so the panel can show it before it
/// leaves.
enum DictationEvent: Equatable {
    /// The recording waits for the model to download or get ready.
    case waitingForModel
    /// The model failed to load. The recording is kept, and the next load that succeeds
    /// transcribes it.
    case recordingKept
}
