import Darwin
import Foundation

/// Finds the address a receiver on the local network can reach this Mac at.
enum LocalNetworkAddress {
    /// IPv4 address of an active, non-loopback interface.
    ///
    /// Wi-Fi and Ethernet interfaces are preferred, because a Cast device reaches the
    /// Mac over the same network. Returns `nil` when no interface qualifies.
    static func primaryIPv4() -> String? {
        var addresses: [(interface: String, address: String)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            return nil
        }
        defer { freeifaddrs(head) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let flags = interface.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }
            let interfaceName = String(validatingCString: interface.ifa_name) ?? ""
            let address = String(decoding: host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            addresses.append((interfaceName, address))
        }

        let preferredInterfaces = ["en0", "en1"]
        if let preferred = addresses.first(where: { preferredInterfaces.contains($0.interface) }) {
            return preferred.address
        }
        return addresses.first?.address
    }
}
