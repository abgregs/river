import Carbon.HIToolbox
import Combine
import Foundation
import os

/// Which River action a hot key belongs to. One registration per ID.
struct HotKeyID: Hashable, Sendable {
    let rawValue: UInt32

    static let dictation = HotKeyID(rawValue: 1)
    // The recorder's question to macOS, registered and released at once.
    static let probe = HotKeyID(rawValue: 0xFFFF)
}

/// A registered hot key went down or came up. A release arrives with the
/// modifiers still held, and a held key does not repeat its press.
enum HotKeyEvent: Equatable, Sendable {
    case pressed(HotKeyID)
    case released(HotKeyID)
}

/// What macOS said to a registration.
enum HotKeyRegistration: Equatable, Sendable {
    case registered
    /// Another app holds this key combination exclusively (`eventHotKeyExistsErr`).
    case takenByAnotherApp
    case refused(OSStatus)
}

/// The one owner of `RegisterEventHotKey`, `UnregisterEventHotKey` and
/// `InstallEventHandler` (AGENTS.md rule 3). Not a `Capability`: hot keys need no
/// permission. Every hot key is registered exclusive, so while River holds it the
/// app in front never receives the keystroke. Presses and releases come out as one
/// typed stream, as the event tap's do.
///
/// The Carbon calls are not thread safe; the registry is main-actor isolated and
/// the handler is installed on the application target, which runs on the main
/// thread.
@MainActor
final class HotKeyRegistry {
    /// The OS calls, injected so no test registers a real hot key.
    struct Calls {
        var installHandler: (_ context: UnsafeMutableRawPointer) -> OSStatus
        var register: (_ keyCode: UInt32, _ modifiers: UInt32, _ id: UInt32) -> (OSStatus, EventHotKeyRef?)
        var unregister: (EventHotKeyRef?) -> Void

        static let live = Calls(
            installHandler: { context in
                var eventTypes = [
                    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
                ]
                return InstallEventHandler(
                    GetApplicationEventTarget(), handleHotKeyEvent, eventTypes.count, &eventTypes, context, nil
                )
            },
            register: { keyCode, modifiers, id in
                var ref: EventHotKeyRef?
                let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
                let status = RegisterEventHotKey(
                    keyCode, modifiers, hotKeyID, GetApplicationEventTarget(),
                    OptionBits(kEventHotKeyExclusive), &ref
                )
                return (status, ref)
            },
            unregister: { ref in
                if let ref { UnregisterEventHotKey(ref) }
            }
        )

        /// Accepts every registration and installs nothing. Tests drive events
        /// through `publishForTest`.
        static let inert = Calls(
            installHandler: { _ in noErr },
            register: { _, _, _ in (noErr, nil) },
            unregister: { _ in }
        )
    }

    private struct Registered {
        let keyCode: UInt32
        let modifiers: UInt32
        let ref: EventHotKeyRef?
    }

    private let calls: Calls
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "hotkey")
    private let eventSubject = PassthroughSubject<HotKeyEvent, Never>()
    private var registered: [HotKeyID: Registered] = [:]
    private var handlerInstalled = false

    var events: AnyPublisher<HotKeyEvent, Never> { eventSubject.eraseToAnyPublisher() }

    // internal for testability — which IDs are registered now.
    var registeredIDs: Set<HotKeyID> { Set(registered.keys) }

    init(calls: Calls = .live) {
        self.calls = calls
    }

    /// Registers `keyCode` plus `modifiers` (Carbon modifier bits) under `id`,
    /// exclusive. A key already registered under `id` is unregistered first.
    @discardableResult
    func register(_ id: HotKeyID, keyCode: UInt32, modifiers: UInt32) -> HotKeyRegistration {
        unregister(id)
        if !handlerInstalled {
            // The context holds the registry weakly and is never released: the handler
            // stays installed for the life of the process, so its pointer must too.
            let context = Unmanaged.passRetained(HotKeyHandlerContext(registry: self))
            let status = calls.installHandler(context.toOpaque())
            guard status == noErr else {
                context.release()
                logger.error("InstallEventHandler failed (\(status, privacy: .public))")
                return .refused(status)
            }
            handlerInstalled = true
        }
        let (status, ref) = calls.register(keyCode, modifiers, id.rawValue)
        let result: HotKeyRegistration = switch Int(status) {
        case Int(noErr): .registered
        case eventHotKeyExistsErr: .takenByAnotherApp
        default: .refused(status)
        }
        if result == .registered {
            registered[id] = Registered(keyCode: keyCode, modifiers: modifiers, ref: ref)
        }
        logger.info("Hot key \(id.rawValue, privacy: .public) (keycode \(keyCode, privacy: .public), modifiers \(modifiers, privacy: .public)): \(String(describing: result), privacy: .public)")
        return result
    }

    /// Whether macOS would take `keyCode` plus `modifiers` as an exclusive hot key now:
    /// registered and released at once, so the Settings recorder can refuse a combination
    /// before saving it (spec 0036, Conflicts). Ask while River's own hot keys are
    /// unregistered, or River's own registration reads as another app's.
    func probe(keyCode: UInt32, modifiers: UInt32) -> HotKeyRegistration {
        let result = register(.probe, keyCode: keyCode, modifiers: modifiers)
        unregister(.probe)
        return result
    }

    func unregister(_ id: HotKeyID) {
        guard let existing = registered.removeValue(forKey: id) else { return }
        calls.unregister(existing.ref)
        logger.info("Hot key \(id.rawValue, privacy: .public) unregistered (keycode \(existing.keyCode, privacy: .public))")
    }

    // internal for testability — drives synthetic presses and releases through
    // `events`, the same path the Carbon handler takes.
    func publishForTest(_ event: HotKeyEvent) {
        eventSubject.send(event)
    }

    fileprivate func receive(kind: UInt32, id: UInt32) {
        let hotKeyID = HotKeyID(rawValue: id)
        guard registered[hotKeyID] != nil else { return }
        switch Int(kind) {
        case kEventHotKeyPressed: eventSubject.send(.pressed(hotKeyID))
        case kEventHotKeyReleased: eventSubject.send(.released(hotKeyID))
        default: break
        }
    }
}

// Marks River's hot keys in their `EventHotKeyID`: 'RIVR'.
private let hotKeySignature: OSType = 0x5249_5652

// What the handler reaches through its user data. Holds the registry weakly, so a
// hot key event after the registry is freed finds nil instead of freed memory.
private final class HotKeyHandlerContext {
    weak var registry: HotKeyRegistry?

    init(registry: HotKeyRegistry) {
        self.registry = registry
    }
}

// File-level C callback: captures nothing and recovers the context from user data.
// Installed on the application target, so it runs on the main thread.
private func handleHotKeyEvent(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let kind = GetEventKind(event)
    let context = Unmanaged<HotKeyHandlerContext>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        context.registry?.receive(kind: kind, id: hotKeyID.id)
    }
    return noErr
}
