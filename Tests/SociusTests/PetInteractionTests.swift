import Testing
@testable import Socius

@MainActor @Suite struct PetInteractionTests {
    @Test func lowCareRemainsVisibleDuringAffection() {
        let pet = PetPrototype()
        pet.preview(.hungry)
        pet.pet()
        #expect(pet.mood == .happy)
        #expect(pet.moodLabel == "Hungry")
        #expect(pet.careHP == 12)
        #expect(!pet.toolsAvailable)
        pet.feed()
        #expect(pet.toolsAvailable)
        #expect(pet.careHP == min(pet.fullness, pet.happiness))
    }
    @Test func hungryPetRefusesToolsUntilFed() {
        let pet = PetPrototype()
        pet.preview(.hungry)
        pet.openPocket()
        #expect(!pet.panelOpen)
        #expect(!pet.toolsAvailable)
        pet.feed()
        pet.openPocket()
        #expect(pet.panelOpen)
        #expect(pet.toolsAvailable)
    }
    @Test func snackDoesNotFixGrumpyMood() {
        let pet = PetPrototype()
        pet.preview(.grumpy)
        pet.feed()
        #expect(!pet.toolsAvailable)
        pet.play()
        #expect(pet.toolsAvailable)
    }
    @Test func needsNeverExceedTheirBounds() {
        let pet = PetPrototype()
        for _ in 0..<10 { pet.feed(); pet.play() }
        #expect(pet.fullness == 100)
        #expect(pet.happiness == 100)
        for _ in 0..<2000 { pet.tick() }
        #expect(pet.fullness == 0)
        #expect(pet.happiness == 0)
        #expect(!pet.toolsAvailable)
    }
    @Test func sleepPausesNeeds() {
        let pet = PetPrototype()
        pet.sleep()
        let fullness = pet.fullness
        let happiness = pet.happiness
        for _ in 0..<60 { pet.tick() }
        #expect(pet.fullness == fullness)
        #expect(pet.happiness == happiness)
        pet.sleep()
        #expect(pet.mood == .happy)
    }
    @Test func pocketClosesWhenNeedsDropBelowThreshold() {
        let pet = PetPrototype()
        pet.fullness = 20.1
        pet.openPocket()
        #expect(pet.panelOpen)
        pet.tick()
        #expect(!pet.panelOpen)
    }
    @Test func offeringRequiresAcceptanceBeforeReward() {
        let pet = PetPrototype()
        pet.preview(.hungry)
        pet.offer(.snack)
        #expect(!pet.toolsAvailable)
        #expect(pet.offering == .snack)
        pet.acceptOffering()
        #expect(pet.toolsAvailable)
        #expect(pet.offering == nil)
        #expect(pet.mood == .eating)
    }
    @Test func dragDropAcceptsOnlyKnownCareItems() {
        let pet = PetPrototype()
        pet.preview(.grumpy)
        #expect(!pet.receive("unrelated clipboard text"))
        #expect(!pet.toolsAvailable)
        #expect(pet.receive("shell"))
        #expect(!pet.toolsAvailable)
        pet.chooseShell(pet.pearlShell)
        #expect(pet.toolsAvailable)
        #expect(pet.mood == .playing)
    }
    @Test func restRequestDoesNotToggleSleepingPetAwake() {
        let pet = PetPrototype()
        #expect(pet.receive("rest"))
        #expect(pet.mood == .sleeping)
        #expect(pet.receive("rest"))
        #expect(pet.mood == .sleeping)
    }
    @Test func shellGameRewardsOnlyFindingThePearl() {
        let pet = PetPrototype()
        pet.preview(.grumpy)
        pet.startShellGame(prize: 2)
        let before = pet.happiness
        pet.chooseShell(0)
        #expect(pet.shellGameActive)
        #expect(pet.happiness == before)
        #expect(pet.emptyShells == [0])
        pet.chooseShell(2)
        #expect(!pet.shellGameActive)
        #expect(pet.happiness == before + 45)
        pet.chooseShell(2)
        #expect(pet.happiness == before + 45)
    }
    @Test func feedingInterruptsShellGame() {
        let pet = PetPrototype()
        pet.startShellGame(prize: 1)
        pet.feed()
        #expect(!pet.shellGameActive)
        #expect(pet.mood == .eating)
    }
    @Test func affectionEndsQuickly() async throws {
        let pet = PetPrototype()
        pet.pet()
        #expect(pet.mood == .happy)
        try await Task.sleep(for: .milliseconds(850))
        #expect(pet.mood == .content)
    }
}
