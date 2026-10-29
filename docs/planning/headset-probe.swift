// Step 0 probe for docs/planning/0033_warm-microphone-pre-roll.md.
//
// Question: with AirPods connected and set as the default OUTPUT, does an
// AVAudioEngine whose input node is pinned to the built-in microphone leave the
// AirPods in high-quality audio (A2DP), or does it still pull them into call
// mode (HFP)?
//
// Build and run (from the repo root; the terminal needs Microphone permission):
//
//   swiftc -O docs/planning/headset-probe.swift -o /tmp/headset-probe
//   /tmp/headset-probe builtin 30     # decision 4: pin the input to the built-in mic
//   /tmp/headset-probe default 30     # control: today's behaviour, default input
//   /tmp/headset-probe auhal 30       # 2026-10-25: raw HAL output unit, device pinned
//                                     # BEFORE AudioUnitInitialize;
//                                     # never touches AVAudioEngine or the default device
//   /tmp/headset-probe audioqueue 30  # 2026-10-26: AudioQueue input, device pinned by UID
//                                     # before AudioQueueStart
//   /tmp/headset-probe avcapture 30   # 2026-10-26: AVCaptureSession with the built-in
//                                     # AVCaptureDevice as its input
//
// Before starting: connect the AirPods, choose them as the output in System
// Settings > Sound, and start music. Watch the output device's nominal sample
// rate below while the probe runs. A2DP keeps it at 44100 or 48000 Hz; HFP
// drops it to 8000-24000 Hz. The probe also tails the unified log for the
// HFP / A2DP / GetBestSampleRate lines the 2026-09-24 trace showed.
//
// Throwaway: not part of the River target, not a test, no River types.

import AVFoundation
import CoreAudio
import Foundation

// MARK: - CoreAudio helpers

func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func read<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) -> T? {
    var addr = address(selector, scope: scope)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
    }
    return status == noErr ? value : nil
}

func deviceName(_ id: AudioDeviceID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let name else { return "?" }
    return name.takeRetainedValue() as String
}

func transportName(_ id: AudioDeviceID) -> String {
    guard let t: UInt32 = read(kAudioDevicePropertyTransportType, of: id, initial: 0) else { return "?" }
    switch t {
    case kAudioDeviceTransportTypeBuiltIn: return "builtin"
    case kAudioDeviceTransportTypeBluetooth: return "bluetooth"
    case kAudioDeviceTransportTypeBluetoothLE: return "bluetoothLE"
    case kAudioDeviceTransportTypeUSB: return "usb"
    case kAudioDeviceTransportTypeAggregate: return "aggregate"
    case kAudioDeviceTransportTypeVirtual: return "virtual"
    default: return String(format: "0x%08x", t)
    }
}

func isBluetooth(_ id: AudioDeviceID) -> Bool {
    let t: UInt32 = read(kAudioDevicePropertyTransportType, of: id, initial: 0) ?? 0
    return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
}

func hasInput(_ id: AudioDeviceID) -> Bool {
    var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
    return size / UInt32(MemoryLayout<AudioStreamID>.size) > 0
}

func nominalRate(_ id: AudioDeviceID) -> Double {
    read(kAudioDevicePropertyNominalSampleRate, of: id, initial: Float64(0)) ?? 0
}

func allDevices() -> [AudioDeviceID] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
    read(selector, of: AudioObjectID(kAudioObjectSystemObject), initial: AudioDeviceID(0)) ?? 0
}

func describe(_ id: AudioDeviceID) -> String {
    "\(deviceName(id)) [\(transportName(id)), \(Int(nominalRate(id))) Hz, id \(id)]"
}

// MARK: - Timeline

let t0 = Date()
func mark(_ message: String) {
    let dt = Date().timeIntervalSince(t0)
    print(String(format: "+%6.2fs  %@", dt, message))
    fflush(stdout)
}

// MARK: - Arguments

let mode = CommandLine.arguments.dropFirst().first ?? "builtin"
let seconds = Double(CommandLine.arguments.dropFirst(2).first ?? "30") ?? 30
let modes = ["builtin", "default", "auhal", "audioqueue", "avcapture"]
guard modes.contains(mode) else {
    print("usage: headset-probe [\(modes.joined(separator: "|"))] [seconds]")
    exit(2)
}

// MARK: - Inventory before anything touches audio

mark("mode=\(mode) duration=\(Int(seconds))s")
let devices = allDevices()
for id in devices {
    mark("device: \(describe(id))\(hasInput(id) ? " (input)" : "")")
}
let initialOutput = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
let initialInput = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
mark("default output: \(describe(initialOutput))")
mark("default input:  \(describe(initialInput))")
guard isBluetooth(initialOutput) else {
    mark("the default output is not a Bluetooth device; the probe answers nothing. Pick the AirPods as output and rerun.")
    exit(2)
}

// A previous run leaves the AirPods in call mode for a while. Wait for them to
// come back to an A2DP rate before touching audio, so each run starts clean.
if nominalRate(initialOutput) < 44100 {
    mark("output is at \(Int(nominalRate(initialOutput))) Hz (call mode); waiting up to 90 s for it to return to A2DP. Keep the music playing.")
    let deadline = Date(timeIntervalSinceNow: 90)
    while nominalRate(initialOutput) < 44100, Date() < deadline {
        Thread.sleep(forTimeInterval: 1)
    }
    if nominalRate(initialOutput) < 44100 {
        mark("INCONCLUSIVE: output never returned to A2DP. Reconnect the AirPods or toggle Bluetooth, then rerun.")
        exit(2)
    }
    mark("output back at \(Int(nominalRate(initialOutput))) Hz")
}

let builtInInput = devices.first { hasInput($0) && transportName($0) == "builtin" }
guard let builtInInput else {
    mark("no built-in input device found")
    exit(2)
}
mark("built-in input: \(describe(builtInInput))")

// MARK: - Watch the defaults and the output rate

var listeners: [AudioObjectPropertyAddress] = [
    address(kAudioHardwarePropertyDefaultOutputDevice),
    address(kAudioHardwarePropertyDefaultInputDevice),
]
for i in listeners.indices {
    let selector = listeners[i].mSelector
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listeners[i], DispatchQueue.main) { _, _ in
        let which = selector == kAudioHardwarePropertyDefaultOutputDevice ? "output" : "input"
        mark("HAL: default \(which) changed -> \(describe(defaultDevice(selector)))")
    }
}

var minOutputRate = nominalRate(initialOutput)
var lastOutputRate = minOutputRate
var defaultsChanged = false
let poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    let out = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
    let rate = nominalRate(out)
    if out != initialOutput || defaultDevice(kAudioHardwarePropertyDefaultInputDevice) != initialInput {
        defaultsChanged = true
    }
    if rate != lastOutputRate {
        mark("output rate: \(Int(lastOutputRate)) -> \(Int(rate)) Hz on \(deviceName(out))")
        lastOutputRate = rate
    }
    if out == initialOutput, rate > 0 { minOutputRate = min(minOutputRate, rate) }
}

// MARK: - Tail the unified log for the Bluetooth / CoreAudio lines

let log = Process()
log.executableURL = URL(fileURLWithPath: "/usr/bin/log")
log.arguments = [
    "stream", "--style", "compact",
    "--predicate",
    "(process == \"headset-probe\" OR process == \"bluetoothd\" OR process == \"coreaudiod\") AND "
        + "(eventMessage CONTAINS[c] \"HFP\" OR eventMessage CONTAINS[c] \"A2DP\" OR eventMessage CONTAINS[c] \"SCO\" "
        + "OR eventMessage CONTAINS \"GetBestSampleRate\" OR eventMessage CONTAINS \"SelectDevice\")",
]
let logPipe = Pipe()
log.standardOutput = logPipe
log.standardError = FileHandle.nullDevice
logPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
    for line in text.split(separator: "\n") where !line.hasPrefix("Filtering") {
        print("         [log] \(line)")
    }
    fflush(stdout)
}
try? log.run()

// MARK: - Raw HAL output unit, pinned before initialise (mode auhal)

var auBuffers = 0
var auLastRMS: Float = 0
var auUnit: AudioUnit?
let auCapacityFrames = 16_384
let auData = UnsafeMutablePointer<Float>.allocate(capacity: auCapacityFrames)
let auList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)

let auInputProc: AURenderCallback = { _, flags, timeStamp, bus, frames, _ in
    guard let unit = auUnit, Int(frames) <= auCapacityFrames else { return noErr }
    auList.pointee.mNumberBuffers = 1
    auList.pointee.mBuffers.mNumberChannels = 1
    auList.pointee.mBuffers.mDataByteSize = frames * 4
    auList.pointee.mBuffers.mData = UnsafeMutableRawPointer(auData)
    let status = AudioUnitRender(unit, flags, timeStamp, bus, frames, auList)
    if status == noErr {
        var sum: Float = 0
        for i in 0..<Int(frames) { sum += auData[i] * auData[i] }
        auLastRMS = (sum / Float(frames)).squareRoot()
        auBuffers += 1
    }
    return status
}

func check(_ what: String, _ status: OSStatus) {
    mark("\(what): status \(status)\(status == noErr ? "" : "  <-- FAILED")")
}

if mode == "auhal" {
    var desc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                         componentSubType: kAudioUnitSubType_HALOutput,
                                         componentManufacturer: kAudioUnitManufacturer_Apple,
                                         componentFlags: 0, componentFlagsMask: 0)
    guard let component = AudioComponentFindNext(nil, &desc) else { mark("no HAL output component"); exit(1) }
    var unit: AudioUnit?
    check("AudioComponentInstanceNew", AudioComponentInstanceNew(component, &unit))
    guard let unit else { exit(1) }
    auUnit = unit
    mark("HAL unit created (default input still: \(describe(defaultDevice(kAudioHardwarePropertyDefaultInputDevice))))")

    var one: UInt32 = 1, zero: UInt32 = 0
    check("enable input (element 1)", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, 4))
    check("disable output (element 0)", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &zero, 4))

    var device = builtInInput
    check("pin device -> built-in BEFORE initialise",
          AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)))
    var readBack: AudioDeviceID = 0
    var idSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &readBack, &idSize)
    mark("unit device reads back as: \(describe(readBack))")

    var deviceFormat = AudioStreamBasicDescription()
    var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    check("read device format (input scope, element 1)",
          AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &deviceFormat, &asbdSize))
    mark("device format: \(Int(deviceFormat.mSampleRate)) Hz, \(deviceFormat.mChannelsPerFrame) ch")
    var client = AudioStreamBasicDescription(mSampleRate: deviceFormat.mSampleRate, mFormatID: kAudioFormatLinearPCM,
                                             mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                                             mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                             mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
    check("set client format (output scope, element 1): Float32 mono",
          AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client, asbdSize))

    var callback = AURenderCallbackStruct(inputProc: auInputProc, inputProcRefCon: nil)
    check("set input callback", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                                     &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
    check("AudioUnitInitialize", AudioUnitInitialize(unit))
    AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &readBack, &idSize)
    mark("after initialise, unit device: \(describe(readBack)); default input: \(describe(defaultDevice(kAudioHardwarePropertyDefaultInputDevice)))")
    check("AudioOutputUnitStart", AudioOutputUnitStart(unit))

    let auProgress = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        mark(String(format: "buffers=%d  rms=%.4f  output rate now %d Hz", auBuffers, auLastRMS,
                    Int(nominalRate(defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)))))
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    poll.invalidate()
    auProgress.invalidate()
    AudioOutputUnitStop(unit)
    AudioUnitUninitialize(unit)
    AudioComponentInstanceDispose(unit)
    log.terminate()
    mark("HAL unit stopped")

    print("")
    print("Summary (auhal)")
    print("  default output at start:   \(describe(initialOutput))")
    print("  default input at start:    \(describe(initialInput))")
    print("  HAL unit captured at:      \(Int(deviceFormat.mSampleRate)) Hz from \(deviceName(readBack)), \(auBuffers) buffers in \(Int(seconds)) s (~\(Int(Double(auBuffers) / seconds)) per s)")
    print("  lowest output rate seen:   \(Int(minOutputRate)) Hz")
    print("  default devices changed:   \(defaultsChanged ? "YES" : "no")")
    let pass = minOutputRate >= 44100 && !defaultsChanged && auBuffers > 0
    print("")
    print(pass
        ? "PASS: a HAL unit pinned to the built-in mic before initialise captured audio and the AirPods stayed at A2DP rates. Decision 4 can become: automatic selection avoids a Bluetooth input."
        : "FAIL: the AirPods dropped to a call-mode rate, the defaults switched, or nothing was captured. The pinned-unit route does not avoid HFP from this process.")
    exit(0)
}

// MARK: - Shared summary for the pinned-device modes

func deviceUID(_ id: AudioDeviceID) -> String {
    var addr = address(kAudioDevicePropertyDeviceUID)
    var uid: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &uid) == noErr, let uid else { return "" }
    return uid.takeRetainedValue() as String
}

func summarize(_ label: String, captured: String, buffers: Int, route: String) -> Never {
    print("")
    print("Summary (\(label))")
    print("  default output at start:   \(describe(initialOutput))")
    print("  default input at start:    \(describe(initialInput))")
    print("  captured:                  \(captured), \(buffers) buffers in \(Int(seconds)) s (~\(Int(Double(buffers) / seconds)) per s)")
    print("  lowest output rate seen:   \(Int(minOutputRate)) Hz")
    print("  default devices changed:   \(defaultsChanged ? "YES" : "no")")
    let pass = minOutputRate >= 44100 && !defaultsChanged && buffers > 0
    print("")
    print(pass
        ? "PASS: \(route) captured audio from the built-in mic and the AirPods stayed at A2DP rates. Decision 4 can become: automatic selection avoids a Bluetooth input."
        : "FAIL: the AirPods dropped to a call-mode rate, the defaults switched, or nothing was captured. \(route) does not avoid HFP from this process.")
    exit(0)
}

// MARK: - AudioQueue input, device pinned by UID before start (mode audioqueue)

var aqBuffers = 0
var aqLastRMS: Float = 0

let aqInputProc: AudioQueueInputCallback = { _, queue, buffer, _, _, _ in
    let frames = Int(buffer.pointee.mAudioDataByteSize) / 4
    if frames > 0 {
        let data = buffer.pointee.mAudioData.assumingMemoryBound(to: Float.self)
        var sum: Float = 0
        for i in 0..<frames { sum += data[i] * data[i] }
        aqLastRMS = (sum / Float(frames)).squareRoot()
        aqBuffers += 1
    }
    AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
}

if mode == "audioqueue" {
    let rate = nominalRate(builtInInput)
    var format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                             mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                             mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                             mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
    var queue: AudioQueueRef?
    check("AudioQueueNewInput (\(Int(rate)) Hz Float32 mono)", AudioQueueNewInput(&format, aqInputProc, nil, nil, nil, 0, &queue))
    guard let queue else { exit(1) }
    mark("queue created (default input still: \(describe(defaultDevice(kAudioHardwarePropertyDefaultInputDevice))))")

    let uid = deviceUID(builtInInput)
    // The property value is the CFStringRef itself. Retained on purpose (and leaked; throwaway):
    // an unretained bridged string was freed before CoreAudio read it and the set call hung.
    var uidRef = Unmanaged.passRetained(uid as CFString)
    check("pin device -> built-in BEFORE start (kAudioQueueProperty_CurrentDevice = \(uid))",
          AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &uidRef, UInt32(MemoryLayout<Unmanaged<CFString>>.size)))
    var readBack: Unmanaged<CFString>?
    var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentDevice, &readBack, &uidSize)
    mark("queue device reads back as: \(readBack.map { $0.takeUnretainedValue() as String } ?? "?")")

    let bytesPerBuffer = UInt32(rate * 0.02) * 4   // 20 ms
    for _ in 0..<3 {
        var buffer: AudioQueueBufferRef?
        check("AudioQueueAllocateBuffer", AudioQueueAllocateBuffer(queue, bytesPerBuffer, &buffer))
        if let buffer { check("AudioQueueEnqueueBuffer", AudioQueueEnqueueBuffer(queue, buffer, 0, nil)) }
    }
    check("AudioQueueStart", AudioQueueStart(queue, nil))
    mark("after start, default input: \(describe(defaultDevice(kAudioHardwarePropertyDefaultInputDevice)))")

    let aqProgress = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        mark(String(format: "buffers=%d  rms=%.4f  output rate now %d Hz", aqBuffers, aqLastRMS,
                    Int(nominalRate(defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)))))
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    poll.invalidate()
    aqProgress.invalidate()
    AudioQueueStop(queue, true)
    AudioQueueDispose(queue, true)
    log.terminate()
    mark("queue stopped")
    summarize("audioqueue", captured: "\(Int(rate)) Hz via AudioQueue pinned to \(deviceName(builtInInput))",
              buffers: aqBuffers, route: "An AudioQueue pinned to the built-in mic before start")
}

// MARK: - AVCaptureSession with the built-in AVCaptureDevice (mode avcapture)

final class CaptureCounter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var buffers = 0
    var lastRMS: Float = 0
    var sampleRate: Double = 0

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        buffers += 1
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return }
        sampleRate = asbd.mSampleRate
        var list = AudioBufferList()
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block)
        guard status == noErr, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32,
              let data = list.mBuffers.mData else { return }
        let frames = Int(list.mBuffers.mDataByteSize) / 4
        guard frames > 0 else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        var sum: Float = 0
        for i in 0..<frames { sum += samples[i] * samples[i] }
        lastRMS = (sum / Float(frames)).squareRoot()
    }
}

if mode == "avcapture" {
    let auth = AVCaptureDevice.authorizationStatus(for: .audio)
    mark("microphone authorization: \(auth.rawValue) (3 = authorized)")
    if auth == .notDetermined {
        let granted = DispatchSemaphore(value: 0)
        AVCaptureDevice.requestAccess(for: .audio) { ok in mark("microphone access granted: \(ok)"); granted.signal() }
        granted.wait()
    }

    let uid = deviceUID(builtInInput)
    let discovered = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    for device in discovered { mark("capture device: \(device.localizedName) uid=\(device.uniqueID)") }
    guard let device = discovered.first(where: { $0.uniqueID == uid }) else {
        mark("no AVCaptureDevice matches the built-in input's UID \(uid)")
        exit(1)
    }
    mark("using capture device: \(device.localizedName)")

    let session = AVCaptureSession()
    let counter = CaptureCounter()
    session.beginConfiguration()
    do {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { mark("cannot add input"); exit(1) }
        session.addInput(input)
    } catch {
        mark("AVCaptureDeviceInput failed: \(error.localizedDescription)")
        exit(1)
    }
    let output = AVCaptureAudioDataOutput()
    output.audioSettings = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsNonInterleaved: false,
        AVNumberOfChannelsKey: 1,
    ]
    output.setSampleBufferDelegate(counter, queue: DispatchQueue(label: "headset-probe.avcapture"))
    guard session.canAddOutput(output) else { mark("cannot add output"); exit(1) }
    session.addOutput(output)
    session.commitConfiguration()
    mark("session configured (default input still: \(describe(defaultDevice(kAudioHardwarePropertyDefaultInputDevice))))")
    session.startRunning()
    mark("session running=\(session.isRunning); default input: \(describe(defaultDevice(kAudioHardwarePropertyDefaultInputDevice)))")

    let avProgress = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        mark(String(format: "buffers=%d  rms=%.4f  captured at %d Hz  output rate now %d Hz", counter.buffers, counter.lastRMS,
                    Int(counter.sampleRate), Int(nominalRate(defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)))))
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    poll.invalidate()
    avProgress.invalidate()
    session.stopRunning()
    log.terminate()
    mark("session stopped")
    summarize("avcapture", captured: "\(Int(counter.sampleRate)) Hz via AVCaptureSession on \(device.localizedName)",
              buffers: counter.buffers, route: "An AVCaptureSession on the built-in AVCaptureDevice")
}

// MARK: - Engine, set up the way MicrophoneCapability does it

mark("creating AVAudioEngine")
let engine = AVAudioEngine()
let input = engine.inputNode   // this creates the AUHAL input unit
mark("input node created (default device at this point: \(describe(defaultDevice(kAudioHardwarePropertyDefaultInputDevice))))")

if mode == "builtin" {
    guard let unit = input.audioUnit else {
        mark("input node has no audio unit")
        exit(1)
    }
    var device = builtInInput
    let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                      &device, UInt32(MemoryLayout<AudioDeviceID>.size))
    mark("set input unit device -> built-in: status \(status)")
    var readBack: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &readBack, &size)
    mark("input unit device reads back as: \(describe(readBack))")
}

let format = input.inputFormat(forBus: 0)
mark("input format: \(Int(format.sampleRate)) Hz, \(format.channelCount) ch")
guard format.sampleRate > 0 else {
    mark("zero sample rate; no input")
    exit(1)
}

var buffers = 0
var lastRMS: Float = 0
input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
    guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
    var sum: Float = 0
    for i in 0..<Int(buffer.frameLength) { sum += data[0][i] * data[0][i] }
    let rms = (sum / Float(buffer.frameLength)).squareRoot()
    DispatchQueue.main.async {
        buffers += 1
        lastRMS = rms
    }
}

NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
    mark("AVAudioEngineConfigurationChange fired; input format now \(Int(engine.inputNode.inputFormat(forBus: 0).sampleRate)) Hz, running=\(engine.isRunning)")
}

do {
    try engine.start()
    mark("engine started")
} catch {
    mark("engine.start failed: \(error.localizedDescription)")
    exit(1)
}

let progress = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    mark(String(format: "buffers=%d  rms=%.4f  running=%@", buffers, lastRMS, engine.isRunning ? "yes" : "no"))
}

// MARK: - Run, then report

RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
poll.invalidate()
progress.invalidate()
input.removeTap(onBus: 0)
engine.stop()
log.terminate()
mark("engine stopped")

print("")
print("Summary (\(mode))")
print("  default output at start:   \(describe(initialOutput))")
print("  default input at start:    \(describe(initialInput))")
print("  input node captured at:    \(Int(format.sampleRate)) Hz, \(buffers) buffers in \(Int(seconds)) s (~\(Int(Double(buffers) / seconds)) per s)")
print("  lowest output rate seen:   \(Int(minOutputRate)) Hz")
print("  default devices changed:   \(defaultsChanged ? "YES" : "no")")
let pass = minOutputRate >= 44100 && !defaultsChanged
print("")
print(pass
    ? "PASS: the AirPods stayed at A2DP rates and the defaults held. Decision 4 stands."
    : "FAIL: the AirPods dropped to a call-mode rate or the defaults switched. Ready mode must not run while a Bluetooth headset is the default input or output.")
exit(0)
