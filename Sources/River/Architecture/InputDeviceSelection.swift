import Foundation

/// Which microphone `MicrophoneCapability` pins its capture unit to.
enum InputDeviceChoice: Equatable {
    case defaultInput
    case builtInMicrophone
}

/// Chooses the capture device from the system default input. A Bluetooth default
/// (AirPods, any headset) is never asked for input: opening a headset's microphone
/// forces it into call mode (HFP), which drops every sound the Mac plays to 8–24 kHz
/// for as long as the input stays open. The built-in microphone is used instead, and
/// the headset keeps its listening quality. Measured 2026-10-26: a HAL unit pinned to
/// the built-in microphone captured 48 kHz audio while connected AirPods stayed at
/// 48 kHz A2DP (warm-microphone spec, decision 4).
///
/// Pure: the capability reads the HAL and passes the facts in, so the rule is tested
/// without CoreAudio.
enum InputDeviceSelection {
    static func choose(defaultInputIsBluetooth: Bool, builtInMicrophoneAvailable: Bool) -> InputDeviceChoice {
        // A Mac with only a headset (a desktop without a built-in microphone) has no
        // better option than the headset.
        defaultInputIsBluetooth && builtInMicrophoneAvailable ? .builtInMicrophone : .defaultInput
    }
}
