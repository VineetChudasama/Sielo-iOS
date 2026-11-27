import Foundation
import Network
import Combine

/// Connectivity monitor mirroring core-network/NetworkHelper.kt
@MainActor
public final class NetworkHelper: ObservableObject {
    public static let shared = NetworkHelper()

    @Published public private(set) var isOnline: Bool = true
    @Published public private(set) var isWifi: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sielo.music.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            let wifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor [weak self] in
                self?.isOnline = online
                self?.isWifi = wifi
            }
        }
        monitor.start(queue: queue)
    }
}
