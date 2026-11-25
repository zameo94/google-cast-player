import Foundation
import Testing
@testable import GoogleCastPlayer

@MainActor
struct CastPowerAssertionTests {
    @Test func holdsAndReleasesOneActivity() {
        let assertion = CastPowerAssertion()

        assertion.begin()
        #expect(assertion.isActive)

        assertion.end()
        #expect(!assertion.isActive)
    }

    @Test func ignoresRepeatedCalls() {
        let assertion = CastPowerAssertion()

        assertion.begin()
        assertion.begin()
        #expect(assertion.isActive)

        assertion.end()
        assertion.end()
        #expect(!assertion.isActive)
    }
}
