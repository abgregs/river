import AppKit
import AudioToolbox
import AVFoundation
import Combine
import CoreAudio
import Foundation
import os

@MainActor
final class MicrophoneCapability: Capability {
    let displayName = "Microphone"

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "permissions")
    private let audioLogger = Logger(subsystem: Constants.loggingSubsystem, category: "audio")
    private let subject: CurrentValueSubject<CapabilityStatus, Never>

    private let audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    // Live input level (0...1), throttled — the recording HUD's level meter reads
    // this so a silent mic is visible *during* capture (planning 0020).
    private let levelSubject = PassthroughSubject<Float, Never>()

    // The capture unit: a HAL output unit with its input element enabled and its
    // output element disabled, pinned to one device before it initialises. Pinning
    // first is what keeps a Bluetooth headset out of call mode when the built-in
    // microphone is chosen instead (`InputDeviceSelection`); `AVAudioEngine` could
    // not do this because its input node binds the system default before any pin
    // (warm-microphone spec, step 0, 2026-10-22 and 2026-10-26).
    private var unit: AudioUnit?
    // The audio-thread half, kept alive for the unit's lifetime (it is the render
    // callback's refCon).
    private var sink: CaptureSink?
    private(set) var captureDevice: AudioDeviceID?
    private(set) var inputFormat: AVAudioFormat?
    private typealias Listener = (object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)
    // System-wide: the default input and the device list. Live between `startEngine`
    // and `stopEngine`.
    private var systemListeners: [Listener] = []
    // On the pinned device: its nominal sample rate and liveness. Live with the unit,
    // because a pinned unit does not follow a format change the way the engine did.
    private var deviceListeners: [Listener] = []
    // True between `startEngine` and `stopEngine`: the window in which a device
    // change is acted on. Also the idempotency guard for both calls.
    private var listening = false
    // internal for testability — counts the device changes the capability handled
    // while listening, so a test can assert the handler is live after `startEngine`
    // and inert after `stopEngine` without a real device (the restart needs one).
    private(set) var deviceChangeCount = 0
    // True while a device-change run is queued. CoreAudio fires the device-list
    // listener 15–19 times per hardware event (measured 2026-10-26); the first
    // callback queues one run on the main actor and the rest of the burst joins it.
    private var deviceChangeScheduled = false

    // Throttle state for the level publisher: `nil` until the first sample so the
    // first buffer always emits. Injectable clock so the ~14 Hz throttle is tested
    // deterministically (planning 0020 acceptance criterion 3).
    private let now: () -> TimeInterval
    private var lastLevelEmit: TimeInterval?

    // internal for testability — when true, `startEngine` opens no capture unit. The
    // test runner often has Microphone permission, so without this the unit starts
    // and real silence (or noise) leaks into tests via the render callback, racing
    // with synthetic buffers from `publishForTest`. The M4 pattern got this for
    // free because `tapCreate` returns nil without Input Monitoring; mic capture
    // has no equivalent natural skip.
    var skipEngineForTesting = false

    // internal for testability — true between `startEngine` and `stopEngine`, so a
    // test sees whether ready mode left the unit running without a real device.
    var isListening: Bool { listening }
    /// Whether the capture unit is running. `startEngine` is idempotent on
    /// `listening`, so a unit that failed to start, or was stopped when its device
    /// vanished, leaves the capability listening with no unit; the manager checks
    /// this at a press and rebuilds the unit instead of trusting the earlier start
    /// (planning 0033, decision 6). Under `skipEngineForTesting` there is never a unit,
    /// so listening stands in for it.
    var isCapturing: Bool { unit != nil || (skipEngineForTesting && listening) }

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }

    /// Buffers from the capture unit, Float32 mono at the device's sample rate.
    /// Subscribers receive on the main actor (the render callback hops via
    /// `Task { @MainActor in ... }` per the threading invariant). Each buffer is
    /// freshly allocated for the callback, so it is the subscriber's to keep.
    var audioBuffers: AnyPublisher<AVAudioPCMBuffer, Never> { audioBufferSubject.eraseToAnyPublisher() }

    /// Throttled input level (0...1) during capture. Emits on the main actor (the
    /// render callback hops via `Task { @MainActor in ... }`, same discipline as the
    /// buffer stream and the event tap). `AppState.bind(microphone:)` subscribes;
    /// the recording HUD renders it (planning 0020).
    var inputLevels: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        subject = CurrentValueSubject(Self.readStatus())
    }

    func recheck() async {
        updateStatus(Self.readStatus())
    }

    /// Microphone is the one permission macOS lets us auto-prompt for. After the
    /// user answers the system dialog, re-read the authoritative status.
    func requestGrant() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        logger.info("Microphone access request resolved: granted=\(granted, privacy: .public)")
        await recheck()
    }

    func openSystemSettings() {
        SystemSettingsPane.microphone.open()
    }

    /// Chooses the capture device, starts the capture unit on it and publishes its
    /// buffers to `audioBuffers`. Idempotent. If the unit fails to start, logs a warning
    /// and returns, mirroring the fail-quiet pattern in `InputMonitoringCapability.startTap`.
    /// A missing Microphone grant does not fail the start: CoreAudio delivers silence
    /// instead, which the silence trim reads as "nothing was said"; the capability's
    /// `status` already reports `.denied`/`.unknown` to onboarding upstream.
    func startEngine() async {
        guard !listening else { return }
        listening = true
        if skipEngineForTesting { return }
        observeDeviceChanges()
        guard let device = selectDevice() else {
            audioLogger.warning("No input device available; capture not started")
            return
        }
        startUnit(on: device)
    }

    /// Stops the capture unit and stops acting on device changes. Idempotent.
    func stopEngine() {
        guard listening else { return }
        listening = false
        removeListeners(&systemListeners)
        stopUnit()
        // Reset the throttle so the next recording's first buffer emits a level
        // immediately rather than being gated by the previous recording's timestamp.
        lastLevelEmit = nil
        audioLogger.info("Capture unit stopped")
    }

    // internal for testability — pushes a synthetic buffer into the stream
    // synchronously on the main actor, bypassing the capture unit (which requires a
    // Microphone grant on the running process).
    func publishForTest(_ buffer: AVAudioPCMBuffer) {
        audioBufferSubject.send(buffer)
    }

    /// A pinned unit does not follow the system default, so the capability listens
    /// to the HAL itself: the default input changing (AirPods connecting, a USB
    /// microphone chosen), the device list changing (the pinned device unplugged),
    /// and the pinned device's own sample rate and liveness (another app changing
    /// the rate). On any of them it re-runs the selection and restarts the unit only
    /// if the answer is a different device or the same device at a new rate; the buffer stream continues in the new
    /// format (`AudioCaptureManager` converts each run of same-format buffers on its
    /// own). AirPods connecting or leaving while the built-in microphone is pinned
    /// changes nothing and costs no restart. A failed restart is logged at `.error`
    /// and the recording's shortfall is what the capture gap watchdog reports
    /// (planning 0032).
    // internal for testability — the listener handler, split out so a test can
    // drive it without a HAL property change.
    func handleDeviceChange() {
        guard listening else { return }
        deviceChangeCount += 1
        guard !skipEngineForTesting else { return }
        guard let device = selectDevice() else {
            audioLogger.error("Audio devices changed and no input device remains; capture has stopped")
            stopUnit()
            return
        }
        if unit != nil, device == captureDevice {
            let rate = CoreAudioDevices.nominalSampleRate(of: device)
            if rate == inputFormat?.sampleRate {
                audioLogger.info("Audio devices changed; capture stays on device \(device, privacy: .public)")
                return
            }
            // The device changed its format under the pinned unit (another app or Audio
            // MIDI Setup set a new rate). The client format no longer matches, so the
            // unit is rebuilt on the same device at the new rate.
            audioLogger.info("Capture device \(device, privacy: .public) changed its sample rate to \(rate, privacy: .public) Hz; restarting the capture unit")
        } else {
            audioLogger.info("Audio devices changed; moving capture to \(CoreAudioDevices.name(of: device)) (device \(device, privacy: .public))")
        }
        stopUnit()
        startUnit(on: device)
    }

    // internal for testability — the listener's entry point, split from the handler
    // so a test can fire a burst without a HAL property change. Coalesces the burst:
    // every callback after the first finds the run already queued and returns.
    func noteDeviceChange() {
        guard !deviceChangeScheduled else { return }
        deviceChangeScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            deviceChangeScheduled = false
            handleDeviceChange()
        }
    }

    // MARK: - Device selection

    private func selectDevice() -> AudioDeviceID? {
        let defaultInput = CoreAudioDevices.defaultInputDevice()
        let builtIn = CoreAudioDevices.builtInInputDevice()
        let choice = InputDeviceSelection.choose(
            defaultInputIsBluetooth: defaultInput.map(CoreAudioDevices.isBluetooth) ?? false,
            builtInMicrophoneAvailable: builtIn != nil
        )
        switch choice {
        case .defaultInput:
            return defaultInput ?? builtIn
        case .builtInMicrophone:
            if let defaultInput {
                audioLogger.info("Default input \(CoreAudioDevices.name(of: defaultInput)) (device \(defaultInput, privacy: .public)) is Bluetooth; capturing from the built-in microphone so it keeps its audio quality")
            }
            return builtIn
        }
    }

    // MARK: - The capture unit

    private func startUnit(on device: AudioDeviceID) {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            audioLogger.warning("No HAL output component; capture not started")
            return
        }
        var created: AudioUnit?
        guard AudioComponentInstanceNew(component, &created) == noErr, let unit = created else {
            audioLogger.warning("Could not create the capture unit")
            return
        }

        // Each step logs its own failure; the unit is disposed on the first one.
        func step(_ what: StaticString, _ status: OSStatus) -> Bool {
            guard status != noErr else { return true }
            audioLogger.warning("Capture unit setup failed at \(what, privacy: .public): status \(status, privacy: .public)")
            AudioComponentInstanceDispose(unit)
            return false
        }

        var enabled: UInt32 = 1
        var disabled: UInt32 = 0
        var pinned = device
        let idSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        // Order matters: enable the input element, disable the output element, pin
        // the device, then read the device's format and set the client format, and
        // only then initialise. Pinning after initialise is what the engine did, and
        // it did not keep the headset out of call mode.
        guard step("enable input", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, 4)),
              step("disable output", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, 4)),
              step("pin device", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &pinned, idSize)),
              step("read device format", AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &deviceFormat, &formatSize))
        else { return }
        guard deviceFormat.mSampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: deviceFormat.mSampleRate, channels: 1) else {
            audioLogger.warning("Capture device \(device, privacy: .public) reports no sample rate; capture not started")
            AudioComponentInstanceDispose(unit)
            return
        }
        var clientFormat = format.streamDescription.pointee
        let sink = CaptureSink(unit: unit, format: format) { [weak self] buffer, rms in
            self?.audioBufferSubject.send(buffer)
            self?.emitLevel(rms: rms)
        }
        var callback = AURenderCallbackStruct(inputProc: captureInputProc, inputProcRefCon: Unmanaged.passUnretained(sink).toOpaque())
        guard step("set client format", AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &clientFormat, formatSize)),
              step("set input callback", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))),
              step("initialise", AudioUnitInitialize(unit))
        else { return }
        // The pin must survive initialise; it is what keeps a headset out of call mode.
        var pinnedAfter: AudioDeviceID = 0
        var pinnedSize = idSize
        if AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &pinnedAfter, &pinnedSize) == noErr,
           pinnedAfter != device {
            audioLogger.error("Capture unit initialised on device \(pinnedAfter, privacy: .public) instead of the selected device \(device, privacy: .public); the pin did not hold")
        }
        // The one gated OS call (AGENTS.md rule 3): capture starts here and nowhere else.
        guard AudioOutputUnitStart(unit) == noErr else {
            audioLogger.warning("AudioOutputUnitStart failed on device \(device, privacy: .public)")
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            return
        }
        self.unit = unit
        self.sink = sink
        captureDevice = device
        inputFormat = format
        listen(to: kAudioDevicePropertyNominalSampleRate, on: device, into: &deviceListeners)
        listen(to: kAudioDevicePropertyDeviceIsAlive, on: device, into: &deviceListeners)
        audioLogger.info("Capture unit started on \(CoreAudioDevices.name(of: device)) (device \(device, privacy: .public)) at \(format.sampleRate, privacy: .public) Hz")
    }

    private func stopUnit() {
        removeListeners(&deviceListeners)
        guard let unit else { return }
        // Stop is synchronous: no render callback runs after it returns, so the sink
        // can be released.
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
        sink = nil
        captureDevice = nil
        inputFormat = nil
    }

    // MARK: - Device listeners

    private func observeDeviceChanges() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        listen(to: kAudioHardwarePropertyDefaultInputDevice, on: system, into: &systemListeners)
        listen(to: kAudioHardwarePropertyDevices, on: system, into: &systemListeners)
    }

    private func listen(to selector: AudioObjectPropertySelector, on object: AudioObjectID, into list: inout [Listener]) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Delivered on the main queue, which is the main actor.
            MainActor.assumeIsolated { self?.noteDeviceChange() }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, .main, block)
        guard status == noErr else {
            audioLogger.warning("Could not listen for audio changes (selector \(selector, privacy: .public) on object \(object, privacy: .public)): status \(status, privacy: .public)")
            return
        }
        list.append((object, address, block))
    }

    // CoreAudio matches a listener by block identity, so the stored block is the one
    // handed back. A non-zero status here means a listener leaked; it is logged so a
    // smoke run shows it, since the `listening` guard would otherwise hide it.
    private func removeListeners(_ list: inout [Listener]) {
        for listener in list {
            var address = listener.address
            let status = AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
            if status != noErr {
                audioLogger.warning("Could not remove an audio listener (selector \(listener.address.mSelector, privacy: .public)): status \(status, privacy: .public)")
            }
        }
        list.removeAll()
    }

    // MARK: - Levels

    // internal for testability — the throttled level emission, split from the render
    // callback so the ~14 Hz throttle is tested with an injected clock without a
    // real device (planning 0020 AC3). Emits the normalized level on the main actor;
    // buffers arriving inside `inputLevelPublishInterval` of the last emission are
    // dropped (the meter doesn't need every buffer).
    func emitLevel(rms: Float) {
        let t = now()
        if let last = lastLevelEmit, t - last < Constants.inputLevelPublishInterval { return }
        lastLevelEmit = t
        levelSubject.send(Self.normalizedLevel(rms: rms))
    }

    // internal for testability — the buffer a render callback hands to
    // `AudioUnitRender`. `frameLength` is set to the slice BEFORE rendering: a fresh
    // `AVAudioPCMBuffer` has `frameLength` 0 and its audio buffer list's
    // `mDataByteSize` follows it, so rendering into it fails with paramErr (-50) and
    // delivers nothing. The first on-device build did exactly that (2026-10-26) and
    // every recording came back empty; the test pins the byte size so it cannot
    // recur silently. Pure and audio-thread-safe.
    nonisolated static func renderBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        return buffer
    }

    // internal for testability — RMS of a buffer's first channel. Pure and
    // audio-thread-safe (no `self`), so the render callback computes it before
    // hopping to the main actor, and tests exercise it on synthetic
    // loud/quiet/silent buffers (planning 0020 AC2).
    nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        let samples = channelData[0]
        var sumSquares: Float = 0
        for i in 0..<count { sumSquares += samples[i] * samples[i] }
        return (sumSquares / Float(count)).squareRoot()
    }

    // internal for testability — maps a linear RMS to a 0...1 meter level. A speech
    // peak near `inputLevelReferenceRMS` lights the full meter; silence is 0; quiet
    // speech sits proportionally low. Clamped so a loud transient can't exceed 1.
    static func normalizedLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        return min(1, rms / Constants.inputLevelReferenceRMS)
    }

    // MARK: - Status

    private func updateStatus(_ next: CapabilityStatus) {
        guard subject.value != next else { return }
        logger.info("Microphone status -> \(String(describing: next), privacy: .public)")
        subject.send(next)
    }

    private static func readStatus() -> CapabilityStatus {
        map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    // `.notDetermined` honestly maps to `.unknown`: we have not asked yet, so we
    // cannot claim either grant or denial. Lowering it to `.denied` would mislabel
    // a promptable state as a hard refusal. Internal for deterministic testing.
    static func map(_ status: AVAuthorizationStatus) -> CapabilityStatus {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }
}

// MARK: - The audio-thread half

/// What the render callback needs and nothing more: the unit to render from, the
/// client format to allocate in, and the main-actor delivery. Immutable after
/// construction apart from the one-shot failure flag, which only the IO thread
/// writes, so it is safe to use from the audio thread while the capability owns it.
private final class CaptureSink: @unchecked Sendable {
    let unit: AudioUnit
    let format: AVAudioFormat
    let deliver: @MainActor (AVAudioPCMBuffer, Float) -> Void
    // Set by the render callback on its first failure so the failure is logged once
    // per unit, not 93 times a second. Only the IO thread touches it.
    var reportedRenderFailure = false

    init(unit: AudioUnit, format: AVAudioFormat, deliver: @escaping @MainActor (AVAudioPCMBuffer, Float) -> Void) {
        self.unit = unit
        self.format = format
        self.deliver = deliver
    }
}

/// The input render callback. Runs on the HAL's IO thread: allocates a buffer for
/// this slice, pulls the input into it, computes the RMS there (pure), and hops to
/// the main actor with both. The buffer is the subscriber's to keep; nothing on the
/// audio thread touches it again.
// File scope so the nonisolated render callback can reach it.
private let captureLogger = Logger(subsystem: Constants.loggingSubsystem, category: "audio")

private let captureInputProc: AURenderCallback = { refCon, flags, timeStamp, bus, frameCount, _ in
    let sink = Unmanaged<CaptureSink>.fromOpaque(refCon).takeUnretainedValue()
    guard let buffer = MicrophoneCapability.renderBuffer(format: sink.format, frameCount: frameCount) else {
        if !sink.reportedRenderFailure {
            sink.reportedRenderFailure = true
            captureLogger.error("Capture unit could not allocate a \(frameCount, privacy: .public) frame buffer; no audio is being delivered")
        }
        return noErr
    }
    let status = AudioUnitRender(sink.unit, flags, timeStamp, bus, frameCount, buffer.mutableAudioBufferList)
    guard status == noErr else {
        // A render that fails returns its status to CoreAudio and nothing reaches the
        // main actor. The first on-device build failed every render this way (-50) with
        // no log line; this is the line it lacked.
        if !sink.reportedRenderFailure {
            sink.reportedRenderFailure = true
            captureLogger.error("AudioUnitRender failed with status \(status, privacy: .public) on the capture unit at \(sink.format.sampleRate, privacy: .public) Hz; no audio is being delivered")
        }
        return status
    }
    let rms = MicrophoneCapability.rms(of: buffer)
    let deliver = sink.deliver
    Task { @MainActor in deliver(buffer, rms) }
    return noErr
}
