import Foundation
import Observation

/// Application state for Cast device discovery.
///
/// The model keeps what the browser reported, the user's selection and one visible
/// state. It never connects to a device: that belongs to the cast communication layer.
@MainActor
@Observable
final class DeviceDiscoveryModel {
    /// What the interface shows about the current search.
    enum State: Equatable {
        /// Browsing started and nothing has been reported yet.
        case searching
        /// Browsing is running; `devices` holds what was found so far.
        case ready
        /// Browsing stopped with an error that is ready for display.
        case failed(String)
    }

    /// Devices currently visible on the network, sorted by name.
    private(set) var devices: [CastDevice] = []
    /// Current search state.
    private(set) var state: State = .searching
    /// Identity of the device the user selected, if any.
    private(set) var selectedDeviceID: String?

    /// How long a search may stay silent before the interface reports an empty result.
    static let emptyResultDelay: Duration = .seconds(5)

    private let browser: any CastDeviceBrowsing

    init(browser: any CastDeviceBrowsing = BonjourCastDeviceBrowser()) {
        self.browser = browser
    }

    /// The selected device, resolved against the devices currently visible.
    var selectedDevice: CastDevice? {
        guard let selectedDeviceID else {
            return nil
        }
        return devices.first { $0.id == selectedDeviceID }
    }

    /// Starts browsing and keeps the state updated until the calling task is cancelled.
    func run() async {
        devices.removeAll()
        selectedDeviceID = nil
        state = .searching

        let emptyResultDeadline = Task {
            try? await Task.sleep(for: Self.emptyResultDelay)
            if !Task.isCancelled, state == .searching {
                state = .ready
            }
        }
        defer { emptyResultDeadline.cancel() }

        for await event in browser.events() {
            handleDiscoveryEvent(event)
        }
        if state == .searching {
            state = .ready
        }
    }

    /// Applies one discovery event to the visible state.
    func handleDiscoveryEvent(_ event: CastDiscoveryEvent) {
        switch event {
        case let .deviceAdded(device):
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index] = device
            } else {
                devices.append(device)
                devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            state = .ready
        case let .deviceRemoved(id):
            devices.removeAll { $0.id == id }
            if selectedDeviceID == id {
                selectedDeviceID = nil
            }
            state = .ready
        case let .failed(message):
            state = .failed(message)
        }
    }

    /// Selects a device that is currently visible.
    func selectDevice(id: String) {
        guard devices.contains(where: { $0.id == id }) else {
            return
        }
        selectedDeviceID = id
    }

    /// Clears the current device selection.
    func clearSelection() {
        selectedDeviceID = nil
    }
}
