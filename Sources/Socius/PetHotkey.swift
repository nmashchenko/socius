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
    private var registeredShortcut: PetShortcut?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    func register(_ shortcut: PetShortcut) -> Bool {
        if reference != nil, registeredShortcut == shortcut { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                    identifier.signature == 0x534f4349, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<PetHotkey>.fromOpaque(context).takeUnretainedValue().action?()
                }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return false }
        }
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(shortcut.key, shortcut.modifiers,
            EventHotKeyID(signature: 0x534f4349, id: 1), GetApplicationEventTarget(), 0, &replacement) == noErr else { return false }
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement
        registeredShortcut = shortcut
        return true
    }
    func stop() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil; registeredShortcut = nil
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
                Text("Summon your pet").font(.system(size: 12, weight: .semibold))
                Spacer()
                if recording {
                    Button("Cancel") { stopRecording() }.buttonStyle(PocketButtonStyle(compact: true))
                }
                Button(recording ? "Press keys…" : model.shortcut.label) { startRecording() }
                    .buttonStyle(PocketButtonStyle(compact: true))
            }
            Text(model.shortcutError ?? (recording ? "Use Command, Control or Option. Escape cancels." : "Press this shortcut anywhere to bring your pet to the pointer. Click to change."))
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.onDisappear { stopRecording() }
    }
    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false; model.recordingShortcut = false
    }
    private func startRecording() {
        stopRecording(); recording = true; model.recordingShortcut = true
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
            let key = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
            guard !key.isEmpty else { return nil }
            label += event.keyCode == 49 ? "Space" : key
            model.setShortcut(PetShortcut(key: UInt32(event.keyCode), modifiers: modifiers, label: label))
            stopRecording()
            return nil
        }
    }
}
