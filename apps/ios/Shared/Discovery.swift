import Foundation
import Darwin

final class Discovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    var resolved: ((String, [String], Int) -> Void)?
    func start() { stop(); browser.delegate = self; browser.searchForServices(ofType: "_imagebridge._tcp.", inDomain: "local.") }
    func stop() { browser.stop(); services.forEach { $0.stop() }; services.removeAll() }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service); service.delegate = self; service.resolve(withTimeout: 5)
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let txt = sender.txtRecordData(), let idData = NetService.dictionary(fromTXTRecord: txt)["id"],
              let id = String(data: idData, encoding: .utf8), UUID(uuidString: id) != nil else { return }
        let addresses = (sender.addresses ?? []).compactMap { data -> String? in
            guard data.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            return data.withUnsafeBytes { raw in
                guard let pointer = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self), pointer.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(pointer, socklen_t(data.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
                let value = String(cString: host)
                return isPrivateAddress(value) ? value : nil
            }
        }
        if !addresses.isEmpty, (1...65535).contains(sender.port) { resolved?(id, addresses, sender.port) }
    }
}
