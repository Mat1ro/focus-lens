import AppKit
import Carbon
import LensCore
import Observation

enum LensAction: String, Codable, CaseIterable {
    case toggle, spotlight, zoomIn, zoomOut, larger, smaller, shape, pin
    var title: String {
        switch self {
        case .toggle: "Включить / выключить лупу"
        case .spotlight: "Затемнение фона"
        case .zoomIn: "Увеличить масштаб"
        case .zoomOut: "Уменьшить масштаб"
        case .larger: "Увеличить линзу"
        case .smaller: "Уменьшить линзу"
        case .shape: "Следующая форма"
        case .pin: "Закрепить / следовать"
        }
    }

    var defaultShortcut: Shortcut {
        let key: Int = switch self {
        case .toggle: kVK_ANSI_Z
        case .spotlight: kVK_ANSI_X
        case .zoomIn: kVK_ANSI_S
        case .zoomOut: kVK_ANSI_A
        case .larger: kVK_ANSI_W
        case .smaller: kVK_ANSI_Q
        case .shape: kVK_ANSI_C
        case .pin: kVK_ANSI_V
        }
        return Shortcut(keyCode: UInt32(key), modifiers: UInt32(optionKey))
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var title: String {
        var prefix = ""
        if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
        let names: [UInt32: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2",
            20:"3", 21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"−", 28:"8",
            29:"0", 30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 37:"L", 38:"J",
            39:"'", 40:"K", 41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".",
            49:"Space", 50:"`", 123:"←", 124:"→", 125:"↓", 126:"↑"
        ]
        return prefix + (names[keyCode] ?? "Key \(keyCode)")
    }
}

@Observable final class Preferences {
    var options: LensOptions { didSet { save() } }
    var shortcuts: [String: Shortcut] { didSet { save() } }

    private struct Stored: Codable {
        var options: LensOptions
        var shortcuts: [String: Shortcut]
    }
    private let key = "FocusLens.preferences.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        var options = stored?.options ?? LensOptions()
        options.normalize()
        self.options = options
        self.shortcuts = stored?.shortcuts ?? [:]
    }

    func shortcut(for action: LensAction) -> Shortcut { shortcuts[action.rawValue] ?? action.defaultShortcut }
    func reset() { options = LensOptions(); shortcuts = [:] }

    private func save() {
        guard let data = try? JSONEncoder().encode(Stored(options: options, shortcuts: shortcuts)) else { return }
        defaults.set(data, forKey: key)
    }
}
