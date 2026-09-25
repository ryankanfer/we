import Testing
@testable import WE

@MainActor
struct WEAccountInputTests {
    @Test func emailValidationAndNormalization() {
        #expect(WEAccountInput.email("  alex@example.com\n") == "alex@example.com")
        #expect(WEAccountInput.validEmail(" alex@example.com "))
        for value in ["", "alex", "@example.com", "alex@", "a@@b", "alex @example.com"] {
            #expect(!WEAccountInput.validEmail(value))
        }
    }
    @Test func existingPasswordsAreNotSubjectToCreationRules() {
        #expect(WEAccountInput.validSignIn(email: "alex@example.com", password: "short"))
        #expect(!WEAccountInput.validSignIn(email: "alex@example.com", password: ""))
        #expect(!WEAccountInput.validPassword("short", confirmation: "short"))
    }
    @Test func creationRequiresNameAndALongEnoughPassword() {
        #expect(WEAccountInput.validCreation(name: " Alex ", email: "alex@example.com", password: "password"))
        #expect(!WEAccountInput.validCreation(name: " \n", email: "alex@example.com", password: "password"))
        #expect(!WEAccountInput.validCreation(name: "Alex", email: "alex@example.com", password: "short"))
        #expect(!WEAccountInput.validPassword("password ", confirmation: "password"))
    }
}
