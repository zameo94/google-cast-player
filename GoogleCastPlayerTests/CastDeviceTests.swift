import Foundation
import Testing
@testable import GoogleCastPlayer

struct CastDeviceTests {
    @Test func readsTheAdvertisedDescription() {
        let device = CastDevice(
            serviceName: "Chromecast-1234._googlecast._tcp.local.",
            txtRecord: [
                "id": "0f1e2d3c",
                "fn": "Living Room TV",
                "md": "Chromecast with Google TV",
            ]
        )

        #expect(device.id == "Chromecast-1234._googlecast._tcp.local.")
        #expect(device.name == "Living Room TV")
        #expect(device.modelName == "Chromecast with Google TV")
        #expect(device.castIdentifier == "0f1e2d3c")
    }

    @Test func fallsBackToTheServiceName() {
        let device = CastDevice(serviceName: "Chromecast-5678", txtRecord: [:])

        #expect(device.id == "Chromecast-5678")
        #expect(device.name == "Chromecast-5678")
        #expect(device.modelName == nil)
        #expect(device.castIdentifier == nil)
    }

    @Test func treatsEmptyAndBlankValuesAsMissing() {
        let device = CastDevice(
            serviceName: "Chromecast-9012",
            txtRecord: ["id": "", "fn": "   ", "md": ""]
        )

        #expect(device.name == "Chromecast-9012")
        #expect(device.modelName == nil)
        #expect(device.castIdentifier == nil)
    }

    @Test func trimsAdvertisedValues() {
        let device = CastDevice(
            serviceName: "Chromecast-3456",
            txtRecord: ["id": " abc ", "fn": "  Bedroom TV  ", "md": " Google TV Streamer "]
        )

        #expect(device.castIdentifier == "abc")
        #expect(device.name == "Bedroom TV")
        #expect(device.modelName == "Google TV Streamer")
    }

    @Test func keepsIdentityAcrossNameChanges() {
        let first = CastDevice(serviceName: "service", txtRecord: ["fn": "Old Name"])
        let second = CastDevice(serviceName: "service", txtRecord: ["fn": "New Name"])

        #expect(first.id == second.id)
        #expect(first != second)
    }

    @Test func prefersTheReportThatCarriesTheCastIdentifier() {
        let withoutTXT = CastDevice(serviceName: "service", txtRecord: [:])
        let withTXT = CastDevice(serviceName: "service", txtRecord: ["id": "abc", "fn": "Living Room"])

        #expect(withoutTXT.merging(withTXT) == withTXT)
        #expect(withTXT.merging(withoutTXT) == withTXT)
    }

    @Test func doesNotMergeDifferentServices() {
        let first = CastDevice(id: "a", name: "A")
        let second = CastDevice(id: "b", name: "B")

        #expect(first.merging(second) == second)
    }
}
