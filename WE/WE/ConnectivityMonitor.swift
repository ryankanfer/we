import Combine
import Network

@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline: Bool

    private let monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.ryankanfer.WE.connectivity")

    init(startImmediately: Bool = true, initiallyOnline: Bool = true) {
        isOnline = initiallyOnline
        guard startImmediately else {
            monitor = nil
            return
        }

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = isOnline
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor?.cancel()
    }

    func setOnlineForTesting(_ value: Bool) {
        isOnline = value
    }
}
