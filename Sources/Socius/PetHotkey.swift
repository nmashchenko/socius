import AppKit
import Carbon
import SwiftUI

struct PetShortcut: Codable, Equatable {
    var key: UInt32 = 46
    var modifiers: UInt32 = UInt32(controlKey | optionKey)
    var label = "⌃⌥M"
}

final class PetHotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    func register(_ shortcut: PetShortcut) -> Bool {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<PetHotkey>.fromOpaque(context).takeUnretainedValue().action?()
                }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        return RegisterEventHotKey(shortcut.key, shortcut.modifiers,
            EventHotKeyID(signature: 0x534f4349, id: 1), GetApplicationEventTarget(), 0, &reference) == noErr
    }
    func stop() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
}

struct PetShortcutControl: View {
    @Bindable var model: PetModel
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Bring pet to cursor").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(recording ? "Press shortcut…" : model.shortcut.label) { startRecording() }
                    .buttonStyle(PocketButtonStyle(compact: true))
            }
            Text(model.shortcutError ?? (recording ? "Use Command, Control or Option. Escape cancels." : "Works while you’re in other apps."))
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.onDisappear { stopRecording() }
    }
    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false
    }
    private func startRecording() {
        stopRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
            var modifiers: UInt32 = 0
            var label = ""
            if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
            let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            guard !key.isEmpty else { return nil }
            label += event.keyCode == 49 ? "Space" : key
            model.shortcut = PetShortcut(key: UInt32(event.keyCode), modifiers: modifiers, label: label)
            stopRecording()
            return nil
        }
    }
}
