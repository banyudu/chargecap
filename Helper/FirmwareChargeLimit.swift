import Foundation

struct FirmwareReading {
    let activation: UInt8
    let upper: Int
    let lower: Int
}

final class FirmwareChargeLimit {
    private static let activationKey = FourCharCode(fromStaticString: "bfF0")
    private static let upperKey = FourCharCode(fromStaticString: "bfD0")
    private static let lowerKey = FourCharCode(fromStaticString: "bfE0")

    private let operationLock = NSLock()

    func readState(configuration: ChargeCapConfiguration) -> ChargeCapState {
        operationLock.lock()
        defer { operationLock.unlock() }

        do {
            let reading = try read()
            let active = reading.activation == 0x02
            let plausibleUpper = Self.isPlausibleUpper(reading.upper)
            let plausibleLower = Self.isPlausibleLower(reading.lower)

            let upper = active && plausibleUpper ? reading.upper : configuration.upper
            let lower = active && plausibleLower ? reading.lower : configuration.lower
            let warning: String?

            if reading.activation != 0x00 && reading.activation != 0x02 {
                warning = "Unexpected charge-limit activation value \(reading.activation)."
            } else if active && (!plausibleUpper || !plausibleLower || reading.lower >= reading.upper) {
                warning = "Firmware reported unusual limits (\(reading.upper)% / \(reading.lower)%)."
            } else {
                warning = nil
            }

            return ChargeCapState(
                active: active,
                supported: true,
                upper: upper,
                lower: lower,
                rawActivation: Int(reading.activation),
                backend: .firmware,
                availableLimits: [],
                error: warning
            )
        } catch {
            return ChargeCapState(
                active: false,
                supported: false,
                upper: configuration.upper,
                lower: configuration.lower,
                rawActivation: 0,
                backend: .firmware,
                availableLimits: [],
                error: error.localizedDescription
            )
        }
    }

    func setLimit(upper: Int, lower: Int) throws {
        guard Self.isPlausibleUpper(upper), Self.isPlausibleLower(lower), lower < upper else {
            throw ChargeCapError.invalidLimits(upper: upper, lower: lower)
        }

        operationLock.lock()
        defer { operationLock.unlock() }

        try SMC.writeByte(Self.activationKey, value: 0x00)
        do {
            try SMC.writeUInt32LittleEndian(Self.upperKey, value: UInt32(upper))
            try SMC.writeUInt32LittleEndian(Self.lowerKey, value: UInt32(lower))
            try SMC.writeByte(Self.activationKey, value: 0x02)
            try verify(active: true, upper: upper, lower: lower)
        } catch {
            try? SMC.writeByte(Self.activationKey, value: 0x00)
            throw error
        }
    }

    func disableLimit() throws {
        operationLock.lock()
        defer { operationLock.unlock() }

        let current = try read()
        guard current.activation != 0x00 else { return }

        do {
            try SMC.writeByte(Self.activationKey, value: 0x00)
            try verify(active: false, upper: nil, lower: nil)
        } catch {
            if let verification = try? read(), verification.activation == 0x00 {
                return
            }
            throw error
        }
    }

    private func read() throws -> FirmwareReading {
        let activation = try SMC.readByte(Self.activationKey)
        let upper = try SMC.readUInt32LittleEndian(Self.upperKey)
        let lower = try SMC.readUInt32LittleEndian(Self.lowerKey)
        return FirmwareReading(activation: activation, upper: Int(upper), lower: Int(lower))
    }

    private func verify(active: Bool, upper: Int?, lower: Int?) throws {
        var lastError: Error?

        for _ in 0..<4 {
            Thread.sleep(forTimeInterval: 0.12)
            do {
                let reading = try read()
                if active {
                    if reading.activation == 0x02,
                       reading.upper == upper,
                       reading.lower == lower {
                        return
                    }
                    lastError = SMCError.verificationFailed(
                        "read back activation=\(reading.activation), upper=\(reading.upper), lower=\(reading.lower)"
                    )
                } else {
                    if reading.activation == 0x00 {
                        return
                    }
                    lastError = SMCError.verificationFailed(
                        "read back activation=\(reading.activation) instead of 0"
                    )
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? SMCError.verificationFailed("no readback")
    }

    private static func isPlausibleUpper(_ value: Int) -> Bool {
        (ChargeCapConstants.minimumCap...ChargeCapConstants.maximumCap).contains(value)
    }

    private static func isPlausibleLower(_ value: Int) -> Bool {
        (ChargeCapConstants.minimumLower...ChargeCapConstants.maximumCap).contains(value)
    }
}

enum ChargeCapError: LocalizedError {
    case invalidLimits(upper: Int, lower: Int)
    case noSupportedBackend

    var errorDescription: String? {
        switch self {
        case .invalidLimits(let upper, let lower):
            return "Invalid charge limits \(upper)% / \(lower)%. The upper limit must be 50-100% and greater than the lower limit."
        case .noSupportedBackend:
            return "Charge limiting is not available on this Mac."
        }
    }
}
