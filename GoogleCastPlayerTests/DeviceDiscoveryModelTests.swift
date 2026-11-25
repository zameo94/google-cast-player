import Foundation
import Testing
@testable import GoogleCastPlayer

@MainActor
struct DeviceDiscoveryModelTests {
    private func makeModel() -> DeviceDiscoveryModel {
        DeviceDiscoveryModel(browser: SilentCastDeviceBrowser())
    }

    private func device(_ id: String, named name: String) -> CastDevice {
        CastDevice(id: id, name: name, modelName: "Chromecast")
    }

    @Test func startsEmptyAndSearching() {
        let model = makeModel()

        #expect(model.devices.isEmpty)
        #expect(model.state == .searching)
        #expect(model.selectedDeviceID == nil)
    }

    @Test func addsDevicesAndBecomesReady() {
        let model = makeModel()

        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "Living Room")))

        #expect(model.devices.map(\.name) == ["Living Room"])
        #expect(model.state == .ready)
    }

    @Test func keepsDevicesSortedByName() {
        let model = makeModel()

        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "Gamma")))
        model.handleDiscoveryEvent(.deviceAdded(device("2", named: "Alpha")))
        model.handleDiscoveryEvent(.deviceAdded(device("3", named: "Beta")))

        #expect(model.devices.map(\.name) == ["Alpha", "Beta", "Gamma"])
    }

    @Test func updatesADeviceWithoutDuplicatingIt() {
        let model = makeModel()
        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "Old Name")))

        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "New Name")))

        #expect(model.devices.count == 1)
        #expect(model.devices.first?.name == "New Name")
    }

    @Test func removesADeviceThatDisappears() {
        let model = makeModel()
        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "Living Room")))

        model.handleDiscoveryEvent(.deviceRemoved(id: "1"))

        #expect(model.devices.isEmpty)
        #expect(model.state == .ready)
    }

    @Test func clearsASelectionWhenItsDeviceDisappears() {
        let model = makeModel()
        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "Living Room")))
        model.selectDevice(id: "1")

        model.handleDiscoveryEvent(.deviceRemoved(id: "1"))

        #expect(model.selectedDeviceID == nil)
        #expect(model.selectedDevice == nil)
    }

    @Test func keepsSelectionWhenAnotherDeviceDisappears() {
        let model = makeModel()
        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "Living Room")))
        model.handleDiscoveryEvent(.deviceAdded(device("2", named: "Bedroom")))
        model.selectDevice(id: "2")

        model.handleDiscoveryEvent(.deviceRemoved(id: "1"))

        #expect(model.selectedDeviceID == "2")
    }

    @Test func resolvesTheSelectedDevice() {
        let model = makeModel()
        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "Living Room")))

        model.selectDevice(id: "1")

        #expect(model.selectedDevice?.name == "Living Room")
    }

    @Test func ignoresSelectionOfAnUnknownDevice() {
        let model = makeModel()

        model.selectDevice(id: "missing")

        #expect(model.selectedDeviceID == nil)
    }

    @Test func clearsTheSelection() {
        let model = makeModel()
        model.handleDiscoveryEvent(.deviceAdded(device("1", named: "Living Room")))
        model.selectDevice(id: "1")

        model.clearSelection()

        #expect(model.selectedDeviceID == nil)
    }

    @Test func reportsAFailureWithItsMessage() {
        let model = makeModel()

        model.handleDiscoveryEvent(.failed(message: "Local network access is blocked."))

        #expect(model.state == .failed("Local network access is blocked."))
    }
}
