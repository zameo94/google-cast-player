import Foundation
import Testing
@testable import GoogleCastPlayer

struct DiscoveredDeviceSetTests {
    /// Regression: macOS reports the same service once per interface, and one of the
    /// reports can come without its TXT record. The device must appear once.
    @Test func reportsAServiceTwiceAsOneDevice() {
        var set = DiscoveredDeviceSet()
        let withoutTXT = CastDevice(serviceName: "service", txtRecord: [:])
        let withTXT = CastDevice(serviceName: "service", txtRecord: ["id": "abc", "fn": "Living Room"])

        let events = set.apply([withoutTXT, withTXT])

        #expect(events.count == 1)
        #expect(events.first == .deviceAdded(withTXT))
        #expect(set.devicesByID.count == 1)
    }

    @Test func publishesEachNewDeviceOnce() {
        var set = DiscoveredDeviceSet()

        let events = set.apply([
            CastDevice(id: "b", name: "Bedroom"),
            CastDevice(id: "a", name: "Living Room"),
        ])

        #expect(events == [
            .deviceAdded(CastDevice(id: "a", name: "Living Room")),
            .deviceAdded(CastDevice(id: "b", name: "Bedroom")),
        ])
    }

    @Test func staysSilentWhenNothingChanged() {
        var set = DiscoveredDeviceSet()
        let device = CastDevice(id: "a", name: "Living Room")
        _ = set.apply([device])

        let events = set.apply([device])

        #expect(events.isEmpty)
    }

    @Test func publishesAnUpdateWhenTheTXTRecordArrivesLater() {
        var set = DiscoveredDeviceSet()
        let withoutTXT = CastDevice(serviceName: "service", txtRecord: [:])
        _ = set.apply([withoutTXT])
        let withTXT = CastDevice(serviceName: "service", txtRecord: ["id": "abc", "fn": "Living Room"])

        let events = set.apply([withTXT])

        #expect(events == [.deviceAdded(withTXT)])
    }

    @Test func publishesRemovalWhenAServiceDisappears() {
        var set = DiscoveredDeviceSet()
        _ = set.apply([
            CastDevice(id: "a", name: "Living Room"),
            CastDevice(id: "b", name: "Bedroom"),
        ])

        let events = set.apply([CastDevice(id: "a", name: "Living Room")])

        #expect(events == [.deviceRemoved(id: "b")])
        #expect(set.devicesByID.keys.sorted() == ["a"])
    }
}
