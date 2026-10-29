import AVFoundation
import Foundation

/// The most recent `seconds` of audio while the microphone is ready, seeded into the
/// next recording (planning 0033). Buffers arrive about 93 times a second, so eviction
/// is amortised O(1): the oldest are left behind a head index and the array is compacted
/// once the dead prefix outgrows the live part.
struct PreRollWindow {
    let seconds: Double
    private var buffers: [AVAudioPCMBuffer] = []
    private var head = 0
    private(set) var heldSeconds: Double = 0

    init(seconds: Double) {
        self.seconds = seconds
    }

    var isEmpty: Bool { head == buffers.count }

    mutating func append(_ buffer: AVAudioPCMBuffer) {
        buffers.append(buffer)
        heldSeconds += Self.duration(of: buffer)
        // Drop the oldest while the rest still cover the window.
        while head < buffers.count - 1 {
            let oldest = Self.duration(of: buffers[head])
            guard heldSeconds - oldest >= seconds else { break }
            heldSeconds -= oldest
            head += 1
        }
        if head > 64, head * 2 > buffers.count {
            buffers.removeFirst(head)
            head = 0
        }
    }

    /// Hands over the window's audio, oldest first, and empties it.
    mutating func drain() -> [AVAudioPCMBuffer] {
        let live = Array(buffers[head...])
        buffers.removeAll(keepingCapacity: true)
        head = 0
        heldSeconds = 0
        return live
    }

    private static func duration(of buffer: AVAudioPCMBuffer) -> Double {
        Double(buffer.frameLength) / buffer.format.sampleRate
    }
}
