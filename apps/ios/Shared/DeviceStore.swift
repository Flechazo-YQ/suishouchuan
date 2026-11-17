import Foundation
import Security

struct DeviceStore {
    private static var accessGroup: String? {
        return Bundle.main.object(forInfoDictionaryKey: "CommandVKeychainGroup") as? String
    }
    var selectedId: String {
        get { (try? readText("selectedDevice")) ?? "" }
    }
    func select(_ id: String) throws { try writeData(Data(id.utf8), account: "selectedDevice") }
    func clientId() throws -> String {
        if let current = try readText("clientId") { return current }
        let value = UUID().uuidString.lowercased(); try writeData(Data(value.utf8), account: "clientId"); return value
    }
    func devices() throws -> [PairedDevice] {
        guard let data = try readData("devices") else { return [] }
        return try JSONDecoder().decode([PairedDevice].self, from: data)
    }
    private func readText(_ account: String) throws -> String? { try readData(account).flatMap { String(data: $0, encoding: .utf8) } }
    private func readData(_ account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw BridgeError.message("无法读取已配对电脑，请解锁手机后重试") }
        return data
    }
    func save(_ device: PairedDevice) throws {
        var values = try devices().filter { $0.id != device.id }; values.append(device)
        try write(values); try select(device.id)
    }
    func remove(_ id: String) throws {
        let values = try devices().filter { $0.id != id }; try write(values)
        if selectedId == id { try select(values.first?.id ?? "") }
    }
    private func baseQuery(_ account: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "CommandV.PairedDevices", kSecAttrAccount as String: account]
        if let group = Self.accessGroup { query[kSecAttrAccessGroup as String] = group }
        return query
    }
    private func write(_ devices: [PairedDevice]) throws {
        let data = try JSONEncoder().encode(devices)
        try writeData(data, account: "devices")
    }
    private func writeData(_ data: Data, account: String) throws {
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(account)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw BridgeError.message("保存配对失败（\(status)），请重试") }
    }
}
