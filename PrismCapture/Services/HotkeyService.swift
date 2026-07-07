import AppKit
import Carbon

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handler: ((CaptureMode) -> Void)?
    private var modeByHotKeyID: [UInt32: CaptureMode] = [:]
    private var eventHandler: EventHandlerRef?

    func register(handler: @escaping (CaptureMode) -> Void) {
        self.handler = handler
        reregister()
        installEventHandler()
    }

    func reregister() {
        unregister()
        let settings = AppSettings.shared
        install(binding: settings.hotkeyArea, id: 2, mode: .area)
        install(binding: settings.hotkeyFullscreen, id: 3, mode: .fullscreen)
        install(binding: settings.hotkeyWindow, id: 4, mode: .window)
    }

    func unregister() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        modeByHotKeyID.removeAll()
    }

    private func install(binding: HotkeyBinding, id: UInt32, mode: CaptureMode) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052534D), id: id) // 'PRSM'
        RegisterEventHotKey(
            binding.keyCode,
            binding.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        hotKeyRefs.append(hotKeyRef)
        modeByHotKeyID[id] = mode
    }

    private func installEventHandler() {
        if eventHandler != nil { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData else { return noErr }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            Task { @MainActor in
                if let mode = service.modeByHotKeyID[hotKeyID.id] {
                    service.handler?(mode)
                }
            }
            return noErr
        }, 1, &eventType, userData, &eventHandler)
    }
}
