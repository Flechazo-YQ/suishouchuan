import Foundation
import Security

final class PinnedClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let fingerprint: String
    private let addresses: [String]
    private let port: Int
    private let token: String?

    init(device: PairedDevice) {
        fingerprint = device.fingerprint; addresses = device.addresses; port = device.port; token = device.token
    }
    init(invitation: Invitation) {
        fingerprint = invitation.fingerprint; addresses = invitation.addresses; port = invitation.port; token = nil
    }

    func pair(_ invitation: Invitation, clientId: String, name: String) async throws -> PairedDevice {
        struct Body: Encodable { let code: String; let clientId: String; let name: String }
        struct Response: Decodable { let deviceId: String; let name: String; let token: String }
        let body = try JSONEncoder().encode(Body(code: invitation.code, clientId: clientId, name: name))
        let data = try await request(route: "/v1/pair", json: body)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.deviceId == invitation.deviceId, !response.token.isEmpty else { throw BridgeError.message("电脑身份不一致，请重新扫码") }
        return PairedDevice(id: response.deviceId, name: response.name, addresses: invitation.addresses, port: invitation.port, fingerprint: invitation.fingerprint, token: response.token)
    }

    func send(_ payload: UploadPayload, requestId: UUID) async throws -> TransferResult {
        let data = try await request(route: payload.route, payload: payload, requestId: requestId)
        return try JSONDecoder().decode(TransferResult.self, from: data)
    }

    private func request(route: String, json: Data? = nil, payload: UploadPayload? = nil, requestId: UUID? = nil) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 150
        config.urlCache = nil
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var lastError: Error?
        for address in addresses where isPrivateAddress(address) {
            guard (1...65535).contains(port), let url = URL(string: "https://\(address):\(port)\(route)") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            if let payload, let requestId {
                request.setValue(payload.mime, forHTTPHeaderField: "Content-Type")
                request.setValue(requestId.uuidString.lowercased(), forHTTPHeaderField: "X-Request-Id")
                request.setValue(payload.digest, forHTTPHeaderField: "X-Content-SHA256")
                let bytes = try payload.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                request.setValue(String(bytes), forHTTPHeaderField: "Content-Length")
            } else {
                request.httpBody = json
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            do {
                let response: (Data, URLResponse)
                if let payload { response = try await session.upload(for: request, fromFile: payload.file) }
                else { response = try await session.data(for: request) }
                guard response.0.count <= 65536, let http = response.1 as? HTTPURLResponse else { throw BridgeError.message("电脑返回的数据无效") }
                guard (200...299).contains(http.statusCode) else {
                    let result = try? JSONDecoder().decode(TransferResult.self, from: response.0)
                    throw BridgeError.message(result?.error ?? "电脑返回错误 \(http.statusCode)")
                }
                return response.0
            } catch let error as URLError {
                if error.code == .cancelled { throw error }
                lastError = error
            }
        }
        if let error = lastError as? URLError, [.serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed].contains(error.code) {
            throw BridgeError.message("电脑证书验证失败，请重新扫码配对")
        }
        throw BridgeError.message("连接电脑失败。请确认两端连接同一 Wi-Fi、CtrlV 正在运行，并已允许本地网络权限。")
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(trust, 0),
              digestData(SecCertificateCopyData(certificate) as Data) == fingerprint else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        // DHCP changes the IP. The QR-pinned certificate, rather than its hostname, identifies the PC.
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust, nil) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
