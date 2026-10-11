import AppKit
import Carbon.HIToolbox

/// Глобальная клавиша: виртуальный код клавиши + Carbon-маска модификаторов.
struct HotKey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var name: String

    /// Цифра 6 в верхнем ряду. Код не зависит от раскладки.
    static let `default` = HotKey(keyCode: UInt32(kVK_ANSI_6), modifiers: 0, name: "6")

    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + name
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// Название клавиши для показа; `nil`, если клавишу не получается назвать.
    static func keyName(keyCode: UInt16, characters: String?) -> String? {
        if let special = specialNames[Int(keyCode)] { return special }
        guard let text = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        // Служебные символы AppKit для функциональных клавиш (U+F700…U+F8FF).
        if let scalar = text.unicodeScalars.first, (0xF700...0xF8FF).contains(scalar.value) {
            return nil
        }
        return text.uppercased()
    }

    private static let specialNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Пробел", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_ANSI_Keypad0: "Num 0", kVK_ANSI_Keypad1: "Num 1", kVK_ANSI_Keypad2: "Num 2",
        kVK_ANSI_Keypad3: "Num 3", kVK_ANSI_Keypad4: "Num 4", kVK_ANSI_Keypad5: "Num 5",
        kVK_ANSI_Keypad6: "Num 6", kVK_ANSI_Keypad7: "Num 7", kVK_ANSI_Keypad8: "Num 8",
        kVK_ANSI_Keypad9: "Num 9",
    ]
}

/// Регистрирует системную горячую клавишу через Carbon: срабатывает в любом приложении
/// и не требует разрешения «Мониторинг ввода».
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x414D_434B), id: 1) // 'AMCK'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &hotKeyRef)
        return status == OSStatus(noErr)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            DispatchQueue.main.async {
                HotKeyCenter.shared.onPress?()
            }
            return OSStatus(noErr)
        }, 1, &spec, nil, &handlerRef)
    }
}
