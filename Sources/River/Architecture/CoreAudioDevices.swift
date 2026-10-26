import CoreAudio
import Foundation

/// Read-only queries against the CoreAudio HAL, used by `MicrophoneCapability` to
/// choose and describe the capture device. Stateless; every function reads the
/// property once and returns. Listeners and the capture unit itself live in the
/// capability.
enum CoreAudioDevices {
    /// The system default input, or nil when there is none or the HAL still reports a
    /// device that has just been removed.
    static func defaultInputDevice() -> AudioDeviceID? {
        guard let id: AudioDeviceID = read(kAudioHardwarePropertyDefaultInputDevice, of: AudioObjectID(kAudioObjectSystemObject), initial: 0),
              id != kAudioObjectUnknown, allDevices().contains(id) else { return nil }
        return id
    }

    /// The first device with input streams whose transport is built-in: the Mac's own
    /// microphone. Nil on a Mac without one.
    static func builtInInputDevice() -> AudioDeviceID? {
        allDevices().first { hasInputStreams($0) && transportType(of: $0) == kAudioDeviceTransportTypeBuiltIn }
    }

    static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        let transport = transportType(of: id)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    static func name(of id: AudioDeviceID) -> String {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return "device \(id)" }
        return name.takeRetainedValue() as String
    }

    static func nominalSampleRate(of id: AudioDeviceID) -> Double {
        read(kAudioDevicePropertyNominalSampleRate, of: id, initial: Float64(0)) ?? 0
    }

    static func allDevices() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size / UInt32(MemoryLayout<AudioStreamID>.size) > 0
    }

    private static func transportType(of id: AudioDeviceID) -> UInt32 {
        read(kAudioDevicePropertyTransportType, of: id, initial: UInt32(0)) ?? 0
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, initial: T) -> T? {
        var address = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }
}
