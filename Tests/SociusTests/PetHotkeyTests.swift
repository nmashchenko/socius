import AppKit
import Carbon
import Testing
@testable import Socius

@MainActor struct PetHotkeyTests {
    @Test func replacingShortcutReleasesOldKeysAndConflictKeepsNewKeys() throws {
        _ = NSApplication.shared
        let pet = PetHotkey(), other = PetHotkey(), probe = PetHotkey()
        defer { pet.stop(); other.stop(); probe.stop() }
        let modifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let first = PetShortcut(key: 80, modifiers: modifiers, label: "Test F19")
        let second = PetShortcut(key: 79, modifiers: modifiers, label: "Test F18")
        try #require(pet.register(first))
        #expect(pet.register(second))
        try #require(other.register(first))
        #expect(!pet.register(first))
        #expect(!probe.register(second))
    }
}
