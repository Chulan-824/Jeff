import AppKit
import Carbon

/// Global hotkeys via Carbon RegisterEventHotKey — works without any permission
/// and independent of app focus.
///   ⌥⌘D → 划词分析   ⌥⌘S → 截图取词
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Register a hotkey with a caller-chosen id (used to route events).
    func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32 = UInt32(optionKey | cmdKey),
        action: @escaping () -> Void
    ) {
        handlers[id] = action
        installHandler()

        // Re-register: drop the old binding first.
        if let old = hotKeyRefs[id] { UnregisterEventHotKey(old) }

        let hotKeyID = EventHotKeyID(signature: OSType(0x524E_5141), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref)
        hotKeyRefs[id] = ref
        if status != noErr {
            NSLog("Jeff: RegisterEventHotKey id=\(id) failed: \(status)")
        }
    }

    private func installHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard err == noErr else { return OSStatus(eventNotHandledErr) }
                let this = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { this.handlers[hotKeyID.id]?() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }

    func unregister() {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        handlers.removeAll()
    }
}
