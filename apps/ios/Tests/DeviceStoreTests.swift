#if canImport(CommandV)
import XCTest
@testable import CommandV

final class DeviceStoreTests: XCTestCase {
    func testPairingPersistsAndRevokesLocally() throws {
        let store = DeviceStore()
        let previous = store.selectedId
        let device = PairedDevice(id: UUID().uuidString, name: "测试电脑", addresses: ["192.168.1.2"], port: 43821, fingerprint: String(repeating: "a", count: 64), token: "local-test-token")
        defer { try? store.remove(device.id); try? store.select(previous) }
        try store.save(device)
        XCTAssertEqual(try DeviceStore().devices().first(where: { $0.id == device.id })?.token, "local-test-token")
        XCTAssertEqual(DeviceStore().selectedId, device.id)
        var newEndpoint = device
        newEndpoint.addresses = ["192.168.1.9"]
        newEndpoint.port = 43900
        try store.rememberEndpoint(newEndpoint)
        XCTAssertEqual(try DeviceStore().devices().first(where: { $0.id == device.id }), newEndpoint)
        XCTAssertEqual(DeviceStore().selectedId, device.id)
        let clientId = try store.clientId()
        XCTAssertEqual(try DeviceStore().clientId(), clientId)
        try store.remove(device.id)
        try store.rememberEndpoint(newEndpoint)
        XCTAssertFalse(try store.devices().contains(where: { $0.id == device.id }))
    }
}
#endif
