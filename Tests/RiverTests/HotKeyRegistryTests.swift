import Carbon.HIToolbox
import Testing
@testable import River

@Suite("HotKeyRegistry")
struct HotKeyRegistryTests {
    // The Carbon calls are replaced by `CallLog`, so no test registers a real hot key.

    @MainActor
    @Test("an exclusive registration another app already holds is reported as taken")
    func existingRegistrationIsTaken() {
        // macOS answers an exclusive clash with eventHotKeyExistsErr. The recorder needs
        // it as its own case to tell the user which key is unavailable.
        let log = CallLog(status: OSStatus(eventHotKeyExistsErr))
        let registry = HotKeyRegistry(calls: log.calls)
        #expect(registry.register(.dictation, keyCode: 49, modifiers: UInt32(controlKey)) == .takenByAnotherApp)
        #expect(registry.registeredIDs.isEmpty)
    }

    @MainActor
    @Test("any other refusal is reported with its status and leaves nothing registered")
    func otherRefusalCarriesStatus() {
        // Caps Lock as a modifier gives eventInternalErr, for one; a refusal must never
        // be tracked as registered, or unregistering it later would act on nothing.
        let log = CallLog(status: OSStatus(eventInternalErr))
        let registry = HotKeyRegistry(calls: log.calls)
        #expect(registry.register(.dictation, keyCode: 49, modifiers: 0) == .refused(OSStatus(eventInternalErr)))
        #expect(registry.registeredIDs.isEmpty)
    }

    @MainActor
    @Test("registering an ID again replaces its old hot key, and the handler is installed once")
    func reRegisterReplaces() {
        // Two live hot keys for dictation would leave the old one swallowing its
        // keystroke in every app.
        let log = CallLog(status: noErr)
        let registry = HotKeyRegistry(calls: log.calls)
        registry.register(.dictation, keyCode: 49, modifiers: UInt32(controlKey))
        registry.register(.dictation, keyCode: 9, modifiers: UInt32(controlKey))
        #expect(log.registered == [49, 9])
        #expect(log.unregisterCount == 1)
        #expect(log.handlerInstalls == 1)
        #expect(registry.registeredIDs == [.dictation])

        registry.unregister(.dictation)
        registry.unregister(.dictation)            // already gone: no second OS call
        #expect(log.unregisterCount == 2)
        #expect(registry.registeredIDs.isEmpty)
    }

    @MainActor
    @Test("a handler that cannot be installed refuses the registration")
    func handlerFailureRefuses() {
        // Without the handler a registered hot key would swallow its keystroke and
        // deliver nothing to River.
        let log = CallLog(status: noErr, handlerStatus: OSStatus(paramErr))
        let registry = HotKeyRegistry(calls: log.calls)
        #expect(registry.register(.dictation, keyCode: 49, modifiers: 0) == .refused(OSStatus(paramErr)))
        #expect(log.registered.isEmpty)
    }
}

@MainActor
private final class CallLog {
    let status: OSStatus
    let handlerStatus: OSStatus
    var registered: [UInt32] = []
    var unregisterCount = 0
    var handlerInstalls = 0

    init(status: OSStatus, handlerStatus: OSStatus = noErr) {
        self.status = status
        self.handlerStatus = handlerStatus
    }

    var calls: HotKeyRegistry.Calls {
        HotKeyRegistry.Calls(
            installHandler: { _ in self.handlerInstalls += 1; return self.handlerStatus },
            register: { keyCode, _, _ in self.registered.append(keyCode); return (self.status, nil) },
            unregister: { _ in self.unregisterCount += 1 }
        )
    }
}
