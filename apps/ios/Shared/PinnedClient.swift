import Foundation
import Security

final class PinnedClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private static let legacyProbe = "/v1/transfers/00000000-0000-0000-0000-000000000000"
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

    func checkConnection() async -> Bool {
        await verifiedAddress() != nil
    }

    func verifiedAddress() async -> String? {
        guard let token, !token.isEmpty else { return nil }
        do {
            return try await withMediaDeadline(seconds: 8, timeout: .message(String(localized: "Checking connection timed out."))) {
                await withTaskGroup(of: String?.self) { group in
                    for address in Set(self.addresses.filter(isPrivateAddress)) {
                        group.addTask { await self.probe(address) }
                    }
                    for await result in group {
                        if let result { group.cancelAll(); return result }
                    }
                    return nil
                }
            }
        } catch { return nil }
    }

    private func probe(_ address: String) async -> String? {
        do {
            _ = try await request(route: "/v1/presence", method: "GET", timeout: 3, onlyAddress: address)
            return address
        } catch BridgeError.receiver(status: 404, message: _) {
            // Legacy receivers authenticate before looking up the transfer. A missing record is expected.
            guard (try? await request(route: Self.legacyProbe, method: "GET", timeout: 3, onlyAddress: address)) != nil else { return nil }
            return address
        } catch { return nil }
    }

    func pair(_ invitation: Invitation, clientId: String, name: String) async throws -> PairedDevice {
        struct Body: Encodable { let code: String; let clientId: String; let name: String }
        struct Response: Decodable { let deviceId: String; let name: String; let token: String }
        let body = try JSONEncoder().encode(Body(code: invitation.code, clientId: clientId, name: name))
        let data = try await request(route: "/v1/pair", json: body)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.deviceId == invitation.deviceId, !response.token.isEmpty else { throw BridgeError.message(String(localized: "The computer’s identity changed. Scan a new pairing QR code.")) }
        return PairedDevice(id: response.deviceId, name: response.name, addresses: invitation.addresses, port: invitation.port, fingerprint: invitation.fingerprint, token: response.token)
    }

    func send(_ payload: UploadPayload, requestId: UUID) async throws -> TransferResult {
        try await withMediaDeadline(
            seconds: 75,
            timeout: BridgeError.message(String(localized: "Sending timed out. Your items are ready to retry."))
        ) {
            try await self.sendPayload(payload, requestId: requestId)
        }
    }

    private func sendPayload(_ payload: UploadPayload, requestId: UUID) async throws -> TransferResult {
        if payload.imageCount > CaptureBatch.defaultLimit {
            struct Capabilities: Decodable { let maxBatchImages: Int }
            let maxImages: Int
            do {
                let data = try await request(route: "/v1/capabilities", method: "GET")
                maxImages = try JSONDecoder().decode(Capabilities.self, from: data).maxBatchImages
            } catch BridgeError.receiver(status: 404, message: _) {
                maxImages = CaptureBatch.defaultLimit
            }
            guard maxImages >= payload.imageCount else {
                throw BridgeError.message(String(localized: "Update CtrlV or CommandV to send more than 10 images together. Your batch is still here."))
            }
        }
        let data = try await request(route: payload.route, payload: payload, requestId: requestId)
        return try JSONDecoder().decode(TransferResult.self, from: data)
    }

    private func request(route: String, method: String = "POST", json: Data? = nil, payload: UploadPayload? = nil, requestId: UUID? = nil, timeout: TimeInterval = 30, onlyAddress: String? = nil) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = 150
        config.urlCache = nil
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var lastError: Error?
        let candidates = onlyAddress.map { [$0] } ?? addresses
        for address in candidates where isPrivateAddress(address) {
            try Task.checkCancellation()
            guard (1...65535).contains(port), let url = URL(string: "https://\(address):\(port)\(route)") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            if let payload, let requestId {
                request.setValue(payload.mime, forHTTPHeaderField: "Content-Type")
                request.setValue(requestId.uuidString.lowercased(), forHTTPHeaderField: "X-Request-Id")
                request.setValue(payload.digest, forHTTPHeaderField: "X-Content-SHA256")
                let bytes = try payload.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                request.setValue(String(bytes), forHTTPHeaderField: "Content-Length")
            } else if let json {
                request.httpBody = json
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            do {
                let response: (Data, URLResponse)
                if let payload { response = try await session.upload(for: request, fromFile: payload.file) }
                else { response = try await session.data(for: request) }
                guard response.0.count <= 65536, let http = response.1 as? HTTPURLResponse else { throw BridgeError.message(String(localized: "The computer sent an invalid response.")) }
                guard (200...299).contains(http.statusCode) else {
                    let result = try? JSONDecoder().decode(TransferResult.self, from: response.0)
                    if route == Self.legacyProbe, http.statusCode == 404, result?.error == "未找到发送记录，可以重试" {
                        return response.0
                    }
                    let message = receiverError(result?.error, status: http.statusCode, pairing: route == "/v1/pair")
                    throw BridgeError.receiver(status: http.statusCode, message: message)
                }
                return response.0
            } catch let error as URLError {
                if error.code == .cancelled { throw error }
                lastError = error
            }
        }
        if let error = lastError as? URLError, [.serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed].contains(error.code) {
            throw BridgeError.message(String(localized: "Couldn’t verify the computer. Scan a new pairing QR code."))
        }
        throw BridgeError.message(String(localized: "Can’t reach the computer. Check that both devices are on the same Wi-Fi, CtrlV or CommandV is running, and Local Network access is allowed."))
    }

    private func receiverError(_ message: String?, status: Int, pairing: Bool) -> String {
        // Older desktop receivers return Chinese detail without a locale or a stable error code.
        if Bundle.main.preferredLocalizations.first == "zh-Hans", let message, !message.isEmpty { return message }
        switch status {
        case 403 where pairing:
            return String(localized: "Refresh the QR code on your computer and scan it again.")
        case 401:
            return String(localized: "Your pairing is no longer valid. Scan a new QR code.")
        case 413:
            return String(localized: "The selected items are too large for the receiver.")
        case 415:
            return String(localized: "The computer doesn’t support this file type.")
        case 422:
            return String(localized: "The transfer was incomplete or couldn’t be processed. Try sending it again.")
        case 429:
            return String(localized: "The computer is busy. Try again shortly.")
        case 501:
            return String(localized: "Update CtrlV or CommandV on your computer and try again.")
        case 503:
            return String(localized: "Receiving is paused. Resume it on your computer and try again.")
        default:
            return String(localized: "The computer returned error \(status).")
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first,
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
