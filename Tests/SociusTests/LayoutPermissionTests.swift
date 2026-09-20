import Testing
@testable import Socius

@MainActor @Suite struct LayoutPermissionTests {
    @Test func firstRequestUsesOnlySystemPromptAndRetryOpensSettings() {
        var prompts = 0
        var settings = 0
        let service = WindowLayoutService(checkAccess: { false },
            promptForAccess: { prompts += 1 }, openAccessSettings: { settings += 1 })
        service.requestAccess()
        #expect(prompts == 1)
        #expect(settings == 0)
        service.requestAccess()
        #expect(prompts == 1)
        #expect(settings == 1)
    }

    @Test func grantIsDetectedWithoutKeepingThePocketOpen() async throws {
        var allowed = false
        let service = WindowLayoutService(checkAccess: { allowed }, promptForAccess: {}, openAccessSettings: {})
        service.requestAccess()
        #expect(service.message != nil)
        allowed = true
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !service.trusted && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(service.trusted)
        #expect(service.message == nil)
        allowed = false
        service.refreshAccess()
        #expect(!service.trusted)
    }

    @Test func existingGrantDoesNotPrompt() {
        var prompts = 0
        let service = WindowLayoutService(checkAccess: { true },
            promptForAccess: { prompts += 1 }, openAccessSettings: { prompts += 1 })
        service.requestAccess()
        #expect(service.trusted)
        #expect(prompts == 0)
    }
}
