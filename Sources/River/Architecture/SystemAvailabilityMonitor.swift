import AppKit
import Combine
import Foundation

/// Publishes `SystemAvailability` from the workspace's sleep, session and screen-lock
/// notifications, so readiness closes the microphone while the Mac cannot take a
/// dictation (planning 0033, decision 5). Starts available: a launched app is awake
/// and in the active session, and the lock state has no query API, only notifications.
@MainActor
final class SystemAvailabilityMonitor {
    private let subject = CurrentValueSubject<SystemAvailability, Never>(.available)
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    var availability: AnyPublisher<SystemAvailability, Never> { subject.eraseToAnyPublisher() }
    var current: SystemAvailability { subject.value }

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, on: workspace) { $0.isAwake = false }
        observe(NSWorkspace.didWakeNotification, on: workspace) { $0.isAwake = true }
        observe(NSWorkspace.sessionDidResignActiveNotification, on: workspace) { $0.isSessionActive = false }
        observe(NSWorkspace.sessionDidBecomeActiveNotification, on: workspace) { $0.isSessionActive = true }
        let distributed = DistributedNotificationCenter.default()
        observe(Notification.Name("com.apple.screenIsLocked"), on: distributed) { $0.isUnlocked = false }
        observe(Notification.Name("com.apple.screenIsUnlocked"), on: distributed) { $0.isUnlocked = true }
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }

    // internal for testability — drives the published value without a notification,
    // so session tests exercise readiness on the test's own timeline.
    func setForTesting(_ availability: SystemAvailability) {
        update { $0 = availability }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, _ change: @escaping (inout SystemAvailability) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            // Delivered on the main queue, which is the main actor.
            MainActor.assumeIsolated { self?.update(change) }
        }
        tokens.append((center, token))
    }

    private func update(_ change: (inout SystemAvailability) -> Void) {
        var next = subject.value
        change(&next)
        guard next != subject.value else { return }
        subject.send(next)
    }
}
