import Foundation

final class ChargeCapDaemonService: NSObject, ChargeCapHelperXPCProtocol {
    private let queue = DispatchQueue(label: "com.banyudu.chargecap.helper.queue")
    private let firmware = FirmwareChargeLimit()
    private let store = ChargeCapConfigStore()
    private var configuration: ChargeCapConfiguration

    override init() {
        configuration = store.load()
        super.init()
    }

    func fetchState(withReply reply: @escaping (NSData?, NSString?) -> Void) {
        queue.async {
            let state = self.firmware.readState(configuration: self.configuration)
            self.send(state: state, reply: reply)
        }
    }

    func apply(enabled: Bool, upper: Int, lower: Int, withReply reply: @escaping (NSData?, NSString?) -> Void) {
        queue.async {
            let requested = ChargeCapConfiguration(upper: upper, lower: lower)

            do {
                if enabled {
                    try self.firmware.setLimit(upper: requested.upper, lower: requested.lower)
                } else {
                    try self.firmware.disableLimit()
                }
            } catch {
                reply(nil, error.localizedDescription as NSString)
                return
            }

            self.configuration = requested
            self.store.save(requested)

            let state = self.firmware.readState(configuration: requested)
            self.send(state: state, reply: reply)
        }
    }

    private func send(state: ChargeCapState, reply: @escaping (NSData?, NSString?) -> Void) {
        do {
            let data = try JSONEncoder().encode(state)
            reply(data as NSData, nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }
}

final class ChargeCapDaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let service = ChargeCapDaemonService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(ChargeCapConstants.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: ChargeCapHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}
