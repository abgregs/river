import Combine
import Foundation

enum CapabilityStatus: Equatable {
    case granted
    case denied
    case unknown
}

@MainActor
protocol Capability: AnyObject {
    var displayName: String { get }
    /// What River uses the permission for, in one line, under its name in Settings'
    /// Permissions section (planning 0036).
    var usageSummary: String { get }
    /// Onboarding-only instruction text for permissions the user must grant by
    /// hand (Accessibility, Input Monitoring). `nil` when the capability can
    /// auto-prompt (Microphone). Lives on the capability so `OnboardingView`
    /// stays ignorant of concrete types.
    var setupInstructions: String? { get }
    var status: AnyPublisher<CapabilityStatus, Never> { get }
    var currentStatus: CapabilityStatus { get }
    func recheck() async
    /// The action behind the onboarding "Grant" button. Default opens System
    /// Settings; Microphone overrides this to fire the TCC auto-prompt.
    func requestGrant() async
    func openSystemSettings()
}

@MainActor
extension Capability {
    var setupInstructions: String? { nil }
    func requestGrant() async { openSystemSettings() }
}
