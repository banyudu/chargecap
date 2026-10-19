import Foundation

enum HelperClientError: LocalizedError {
    case helperUnavailable(String?)
    case malformedReply

    var errorDescription: String? {
        switch self {
        case .helperUnavailable(let detail):
            if let detail, !detail.isEmpty {
                return "ChargeCapHelper is unavailable: \(detail)"
            }
            return "ChargeCapHelper is unavailable. Approve it in System Settings > General > Login Items & Extensions."
        case .malformedReply:
            return "ChargeCapHelper returned an invalid response."
        }
    }
}

final class HelperClient {
    static let shared = HelperClient()

    private init() {}

    func fetchState() async throws -> ChargeCapState {
        try await call { proxy, reply in
            proxy.fetchState(withReply: reply)
        }
    }

    func apply(enabled: Bool, upper: Int, lower: Int) async throws -> ChargeCapState {
        try await call { proxy, reply in
            proxy.apply(enabled: enabled, upper: upper, lower: lower, withReply: reply)
        }
    }

    private func call(
        _ invoke: @escaping (ChargeCapHelperXPCProtocol, @escaping (NSData?, NSString?) -> Void) -> Void
    ) async throws -> ChargeCapState {
        let connection = NSXPCConnection(
            machServiceName: ChargeCapConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeCapHelperXPCProtocol.self)
        connection.setCodeSigningRequirement(ChargeCapConstants.helperRequirement)

        return try await withCheckedThrowingContinuation { continuation in
            let completionLock = NSLock()
            var completed = false

            func complete(data: NSData?, error: NSString?) {
                completionLock.lock()
                guard !completed else {
                    completionLock.unlock()
                    return
                }
                completed = true
                completionLock.unlock()

                connection.invalidate()

                if let error {
                    continuation.resume(throwing: HelperClientError.helperUnavailable(error as String))
                    return
                }
                guard let data = data as Data? else {
                    continuation.resume(throwing: HelperClientError.malformedReply)
                    return
                }
                do {
                    continuation.resume(returning: try JSONDecoder().decode(ChargeCapState.self, from: data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                complete(data: nil, error: error.localizedDescription as NSString)
            }
            guard let helper = proxy as? ChargeCapHelperXPCProtocol else {
                complete(data: nil, error: "Could not create an XPC proxy." as NSString)
                return
            }

            connection.resume()
            invoke(helper) { data, error in
                complete(data: data, error: error)
            }
        }
    }
}
