import AppKit
import Carbon.HIToolbox

/// ⌥⌘B opens or closes the panel from anywhere. Carbon's hot keys need no Accessibility permission.
@MainActor
enum Hotkey {
    private static var ref: EventHotKeyRef?

    static func register() {
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { StatusItem.togglePanel() }
            }
            return noErr
        }, 1, &spec, nil, nil)
        // "NBAS"
        let id = EventHotKeyID(signature: 0x4E42_4153, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
