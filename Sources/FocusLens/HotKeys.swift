import AppKit
import Carbon
import SwiftUI

final class HotKeyManager {
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    var onAction: ((LensAction) -> Void)?
    private static let signature: OSType = 0x464C4E53 // FLNS

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            // Carbon's application event target is serviced by the main run loop.
            return MainActor.assumeIsolated {
                guard id.signature == HotKeyManager.signature, id.id > 0,
                      Int(id.id) <= LensAction.allCases.count else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onAction?(LensAction.allCases[Int(id.id) - 1])
                return noErr
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult func register(preferences: Preferences) -> [String] {
        unregister()
        var failures: [String] = []
        for (index, action) in LensAction.allCases.enumerated() {
            let shortcut = preferences.shortcut(for: action)
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                            GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { references.append(reference) }
            else { failures.append("\(action.title): \(shortcut.title) уже занято или недоступно") }
        }
        return failures
    }

    func unregister() {
        for reference in references { UnregisterEventHotKey(reference) }
        references.removeAll()
    }

    func shutdown() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var onRecord: (Shortcut?) -> Void
    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onRecord = onRecord
        return view
    }
    func updateNSView(_ nsView: KeyRecorderView, context: Context) { nsView.onRecord = onRecord }
}

final class KeyRecorderView: NSView {
    var onRecord: ((Shortcut?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        record(event)
        return true
    }
    override func keyDown(with event: NSEvent) { record(event) }
    private func record(_ event: NSEvent) {
        if event.keyCode == kVK_Escape { onRecord?(nil); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.control, .option, .command]).isEmpty else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        onRecord?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
    }
}
