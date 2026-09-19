import Testing
@testable import Socius

@MainActor @Suite struct PetInteractionTests {
    @Test(arguments: [19.9, 20.0, 20.1])
    func careThresholdAppliesToBothNeeds(value: Double) {
        let pet = PetModel()
        pet.fullness = value
        #expect(pet.toolsAvailable == (value > 20))
        pet.fullness = 100
        pet.happiness = value
        #expect(pet.toolsAvailable == (value > 20))
    }
    @Test func bothLowNeedsRequireBothKindsOfCare() {
        let pet = PetModel()
        pet.fullness = 0; pet.happiness = 0
        #expect(pet.restingMood == .hungry)
        pet.feed()
        #expect(pet.moodLabel == "Grumpy")
        #expect(!pet.toolsAvailable)
        pet.startShellGame(prize: 1)
        pet.chooseShell(0)
        #expect(!pet.toolsAvailable)
        pet.chooseShell(1)
        #expect(pet.toolsAvailable)
        #expect(pet.fullness == 45)
        #expect(pet.happiness == 45)
    }
    @Test func naturalHungerUpdatesSpeechWithoutInterruptingPlay() {
        let pet = PetModel()
        pet.fullness = 20.1
        pet.tick()
        #expect(pet.mood == .hungry)
        #expect(pet.speech.contains("snack"))
        pet.startShellGame(prize: 1)
        let invitation = pet.speech
        pet.tick()
        #expect(pet.shellGameActive)
        #expect(pet.speech == invitation)
        #expect(pet.moodLabel == "Hungry")
    }
    @Test func sleepCancelsAnInFlightReaction() async throws {
        let pet = PetModel()
        pet.pet()
        pet.sleep()
        try await Task.sleep(for: .seconds(1))
        #expect(pet.mood == .sleeping)
        let needs = pet.careHP
        pet.tick()
        #expect(pet.careHP == needs)
    }
    @Test func lowCareRemainsVisibleDuringAffection() {
        let pet = PetModel()
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
        let pet = PetModel()
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
        let pet = PetModel()
        pet.preview(.grumpy)
        pet.feed()
        #expect(!pet.toolsAvailable)
        pet.play()
        #expect(pet.toolsAvailable)
    }
    @Test func needsNeverExceedTheirBounds() {
        let pet = PetModel()
        for _ in 0..<10 { pet.feed(); pet.play() }
        #expect(pet.fullness == 100)
        #expect(pet.happiness == 100)
        for _ in 0..<2000 { pet.tick() }
        #expect(pet.fullness == 0)
        #expect(pet.happiness == 0)
        #expect(!pet.toolsAvailable)
    }
    @Test func sleepPausesNeeds() {
        let pet = PetModel()
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
        let pet = PetModel()
        pet.fullness = 20.1
        pet.openPocket()
        #expect(pet.panelOpen)
        pet.tick()
        #expect(!pet.panelOpen)
    }
    @Test func offeringRequiresAcceptanceBeforeReward() {
        let pet = PetModel()
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
        let pet = PetModel()
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
        let pet = PetModel()
        #expect(pet.receive("rest"))
        #expect(pet.mood == .sleeping)
        #expect(pet.receive("rest"))
        #expect(pet.mood == .sleeping)
    }
    @Test func shellGameRewardsOnlyFindingThePearl() {
        let pet = PetModel()
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
        let pet = PetModel()
        pet.startShellGame(prize: 1)
        pet.feed()
        #expect(!pet.shellGameActive)
        #expect(pet.mood == .eating)
    }
    @Test func affectionReturnsToRestingMood() async throws {
        let pet = PetModel()
        pet.pet()
        #expect(pet.mood == .happy)
        // Native window tests also use the main actor. Give the reaction task
        // scheduling room on CI, but still fail if it never restores the mood.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while pet.mood == .happy && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(pet.mood == .content)
    }
}
