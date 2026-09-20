import Foundation
import Testing
@testable import Socius

@MainActor struct PetPreferencesTests {
    @Test func settingsPersistAndSettingsCannotBeHidden() {
        let suite = "SociusTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let pet = PetModel(preferences: defaults)
        pet.name = "  Pearl  "
        pet.colorway = .lavender
        pet.sizeAdjustment = 1.2
        pet.shortcut = PetShortcut(key: 35, modifiers: 768, label: "⌘⇧P")
        pet.hiddenTools = ["Music", "Settings"]
        let reopened = PetModel(preferences: defaults)
        #expect(reopened.displayName == "Pearl")
        #expect(reopened.colorway == .lavender)
        #expect(reopened.sizeAdjustment == 1.2)
        #expect(reopened.shortcut == pet.shortcut)
        #expect(!reopened.showsTool("Music"))
        #expect(reopened.showsTool("Settings"))
        reopened.name = "  "
        #expect(reopened.displayName == "Mochi")
    }
    @Test func rejectedShortcutKeepsTheWorkingCombination() {
        let pet = PetModel()
        let previous = pet.shortcut
        pet.shortcutChanged = { pet.shortcutError = "Unavailable" }
        pet.setShortcut(PetShortcut(key: 35, modifiers: 768, label: "⌘⇧P"))
        #expect(pet.shortcut == previous)
        #expect(pet.shortcutError == "Unavailable")
        pet.shortcutChanged = nil
    }

}
