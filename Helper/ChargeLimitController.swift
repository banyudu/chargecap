import Foundation

final class ChargeLimitController {
    private let firmware = FirmwareChargeLimit()
    private let native = NativeChargeLimit()

    func readState(configuration: ChargeCapConfiguration) -> ChargeCapState {
        let firmwareState = firmware.readState(configuration: configuration)
        if firmwareState.supported {
            return firmwareState
        }

        let nativeState = native.readState(configuration: configuration)
        if nativeState.supported {
            return nativeState
        }

        var unavailable = nativeState
        unavailable.backend = .unavailable
        unavailable.supported = false

        let details = [firmwareState.error, nativeState.error]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        unavailable.error = details.isEmpty
            ? "Charge limiting is not available on this Mac."
            : "Charge limiting is not available on this Mac. \(details)"
        return unavailable
    }

    func setLimit(upper: Int, lower: Int) throws -> ChargeCapConfiguration {
        let firmwareState = firmware.readState(configuration: .default)
        if firmwareState.supported {
            do {
                try firmware.setLimit(upper: upper, lower: lower)
                return ChargeCapConfiguration(upper: upper, lower: lower).sanitized()
            } catch {
                guard Self.indicatesMissingBackend(error), native.isSupported else {
                    throw error
                }
            }
        }

        guard native.isSupported else {
            throw ChargeCapError.noSupportedBackend
        }

        let effectiveUpper = try native.setLimit(upper: upper)
        return ChargeCapConfiguration(
            upper: effectiveUpper,
            lower: max(ChargeCapConstants.minimumLower, effectiveUpper - ChargeCapConstants.hysteresis)
        )
    }

    func disableLimit() throws {
        let firmwareState = firmware.readState(configuration: .default)
        if firmwareState.supported {
            do {
                try firmware.disableLimit()
                return
            } catch {
                guard Self.indicatesMissingBackend(error), native.isSupported else {
                    throw error
                }
            }
        }

        guard native.isSupported else {
            throw ChargeCapError.noSupportedBackend
        }
        try native.disable()
    }

    private static func indicatesMissingBackend(_ error: Error) -> Bool {
        guard let smcError = error as? SMCError else { return false }
        switch smcError {
        case .driverNotFound, .failedToOpen, .keyNotFound, .notPrivileged:
            return true
        case .invalidDataSize, .unknown, .verificationFailed:
            return false
        }
    }
}
