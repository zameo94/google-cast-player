import Foundation
import Network

/// A Chromecast or Google TV device found on the local network.
///
/// The type is a plain value: discovery produces it and the interface presents it.
/// It carries no connection state, because discovery does not connect to anything.
struct CastDevice: Identifiable, Equatable, Sendable {
    /// Identity of the device: its Bonjour service instance name.
    ///
    /// The instance name is the only value the network always reports, and it stays
    /// stable while the device advertises itself. The advertised Cast identifier is
    /// kept separately because some results arrive without it.
    let id: String
    /// Name the device advertises, for example "Living Room TV".
    let name: String
    /// Model description the device advertises, when available.
    let modelName: String?
    /// Identifier the Cast protocol advertises in the TXT record, when available.
    let castIdentifier: String?
    /// Bonjour endpoint used to open the connection, when discovery reported it.
    let endpoint: NWEndpoint?

    init(
        id: String,
        name: String,
        modelName: String? = nil,
        castIdentifier: String? = nil,
        endpoint: NWEndpoint? = nil
    ) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.castIdentifier = castIdentifier
        self.endpoint = endpoint
    }

    /// Builds a device from its Bonjour service name and TXT record.
    ///
    /// Cast devices advertise `id`, `fn` (friendly name) and `md` (model). Any of
    /// them can be missing, so the service name is used as a last resort and an
    /// empty value is treated as missing instead of being displayed.
    init(serviceName: String, txtRecord: [String: String]) {
        self.init(
            id: serviceName,
            name: Self.nonEmpty(txtRecord["fn"]) ?? serviceName,
            modelName: Self.nonEmpty(txtRecord["md"]),
            castIdentifier: Self.nonEmpty(txtRecord["id"])
        )
    }

    /// Combines two reports of the same service, preferring the fuller one.
    ///
    /// macOS can report a service twice, once per interface, and one of the two
    /// reports may come without its TXT record. The report carrying the Cast
    /// identifier wins so the device does not lose information.
    func merging(_ other: CastDevice) -> CastDevice {
        guard id == other.id else {
            return other
        }
        let selfIsFuller = (castIdentifier != nil && other.castIdentifier == nil)
            || (endpoint != nil && other.endpoint == nil)
        return selfIsFuller ? self : other
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Tracks the devices reported by the browser and produces the changes to publish.
///
/// The set exists because a browse result is a snapshot: the caller hands over what
/// is visible now, and the set answers which devices appeared, changed or vanished.
struct DiscoveredDeviceSet {
    private(set) var devicesByID: [String: CastDevice] = [:]

    /// Applies the current snapshot and returns the events to publish, in a stable order.
    ///
    /// The snapshot is collapsed first: the same service can be reported more than once,
    /// and processing the reports individually would publish a device twice.
    mutating func apply(_ discovered: [CastDevice]) -> [CastDiscoveryEvent] {
        var snapshot: [String: CastDevice] = [:]
        for device in discovered {
            snapshot[device.id] = snapshot[device.id]?.merging(device) ?? device
        }

        var events: [CastDiscoveryEvent] = []
        var currentIDs: Set<String> = []

        for device in snapshot.values.sorted(by: { $0.id < $1.id }) {
            currentIDs.insert(device.id)
            let merged = devicesByID[device.id]?.merging(device) ?? device
            if devicesByID[device.id] != merged {
                devicesByID[device.id] = merged
                events.append(.deviceAdded(merged))
            }
        }

        for id in devicesByID.keys.sorted() where !currentIDs.contains(id) {
            devicesByID[id] = nil
            events.append(.deviceRemoved(id: id))
        }

        return events
    }
}
