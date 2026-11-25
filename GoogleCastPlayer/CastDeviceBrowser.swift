import Foundation
import Network
import dnssd

/// Events reported while browsing the local network for Cast devices.
enum CastDiscoveryEvent: Equatable, Sendable {
    case deviceAdded(CastDevice)
    case deviceRemoved(id: String)
    case failed(message: String)
}

/// Browses the local network for Cast devices.
protocol CastDeviceBrowsing: Sendable {
    /// Starts browsing and returns the events it produces.
    ///
    /// Browsing stops when the returned stream is cancelled or finished.
    func events() -> AsyncStream<CastDiscoveryEvent>
}

/// Bonjour discovery of Chromecast and Google TV devices.
///
/// Cast devices advertise `_googlecast._tcp` and describe themselves in the TXT
/// record. The browser only listens: it never connects to a device, and it reports
/// a device as lost when the service disappears from the network.
final class BonjourCastDeviceBrowser: CastDeviceBrowsing {
    /// Bonjour service type Cast devices advertise.
    static let serviceType = "_googlecast._tcp"

    static let localNetworkBlockedMessage =
        "Local network access is blocked. Allow it in System Settings > Privacy & Security > Local Network, then search again."

    func events() -> AsyncStream<CastDiscoveryEvent> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "io.github.zameo94.GoogleCastPlayer.discovery")
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: Self.serviceType, domain: "local."),
                using: parameters
            )
            let knownDevices = KnownDevices()

            browser.stateUpdateHandler = { state in
                switch state {
                case let .failed(error):
                    continuation.yield(.failed(message: Self.describe(error)))
                    continuation.finish()
                case .cancelled:
                    continuation.finish()
                case let .waiting(error) where Self.isLocalNetworkBlocked(error):
                    continuation.yield(.failed(message: Self.localNetworkBlockedMessage))
                    continuation.finish()
                default:
                    break
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                let discovered = results.compactMap(Self.device(from:))
                for event in knownDevices.discovered.apply(discovered) {
                    continuation.yield(event)
                }
            }

            continuation.onTermination = { _ in
                browser.cancel()
            }
            browser.start(queue: queue)
        }
    }

    private static func device(from result: NWBrowser.Result) -> CastDevice? {
        guard case let .service(name: serviceName, type: _, domain: _, interface: _) = result.endpoint else {
            return nil
        }
        var txtRecord: [String: String] = [:]
        if case let .bonjour(record) = result.metadata {
            txtRecord = record.dictionary
        }
        return CastDevice(serviceName: serviceName, txtRecord: txtRecord)
    }

    private static func isLocalNetworkBlocked(_ error: NWError) -> Bool {
        if case let .dns(code) = error {
            return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
        }
        return false
    }

    private static func describe(_ error: NWError) -> String {
        if isLocalNetworkBlocked(error) {
            return localNetworkBlockedMessage
        }
        return "Device discovery stopped: \(error.localizedDescription)"
    }
}

/// Browser state touched only by the browser queue.
private final class KnownDevices: @unchecked Sendable {
    var discovered = DiscoveredDeviceSet()
}
