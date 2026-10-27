import Testing
@testable import River

// Decision 4 of the warm-microphone spec: a Bluetooth default input is never opened,
// because opening a headset's microphone drops its playback to call mode. These pin
// the rule so a refactor cannot quietly start asking AirPods for input again.
struct InputDeviceSelectionTests {
    @Test("a Bluetooth default input is replaced by the built-in microphone")
    func bluetoothDefaultUsesBuiltIn() {
        #expect(InputDeviceSelection.choose(defaultInputIsBluetooth: true, builtInMicrophoneAvailable: true) == .builtInMicrophone)
    }

    @Test("a wired or built-in default input is used as is")
    func otherDefaultIsKept() {
        #expect(InputDeviceSelection.choose(defaultInputIsBluetooth: false, builtInMicrophoneAvailable: true) == .defaultInput)
        #expect(InputDeviceSelection.choose(defaultInputIsBluetooth: false, builtInMicrophoneAvailable: false) == .defaultInput)
    }

    @Test("a Mac with no built-in microphone keeps a Bluetooth default: there is nothing better")
    func noBuiltInKeepsBluetooth() {
        #expect(InputDeviceSelection.choose(defaultInputIsBluetooth: true, builtInMicrophoneAvailable: false) == .defaultInput)
    }
}
