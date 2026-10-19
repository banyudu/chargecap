import Foundation

enum PowerUIError: LocalizedError {
    case unsupported
    case noLimits
    case unavailable(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This Mac does not expose the macOS native charge limit."
        case .noLimits:
            return "macOS reported a charge limit but offered no selectable values."
        case .unavailable(let detail):
            return "The macOS native charge limit is unavailable: \(detail)"
        case .verificationFailed(let detail):
            return "macOS did not confirm the charge-limit change: \(detail)"
        }
    }
}

final class NativeChargeLimit {
    private var cachedLimits: [Int]?

    func readState(configuration: ChargeCapConfiguration) -> ChargeCapState {
        do {
            let limits = try usableLimits()
            let reading = try readLimit()
            let active = reading.enabled && reading.limit < ChargeCapConstants.maximumCap
            let upper = active ? reading.limit : snap(configuration.upper, to: limits)

            return ChargeCapState(
                active: active,
                supported: true,
                upper: upper,
                lower: max(0, upper - ChargeCapConstants.hysteresis),
                rawActivation: reading.enabled ? 1 : 0,
                backend: .native,
                availableLimits: limits,
                error: nil
            )
        } catch {
            return ChargeCapState(
                active: false,
                supported: false,
                upper: configuration.upper,
                lower: configuration.lower,
                rawActivation: 0,
                backend: .native,
                availableLimits: [],
                error: error.localizedDescription
            )
        }
    }

    var isSupported: Bool {
        guard chargecap_powerui_is_supported() == 1 else { return false }
        return (try? usableLimits())?.isEmpty == false
    }

    func setLimit(upper: Int) throws -> Int {
        if upper >= ChargeCapConstants.maximumCap {
            try disable()
            return ChargeCapConstants.defaultUpper
        }

        let limits = try usableLimits()
        let target = snap(upper, to: limits)

        do {
            try writeLimit(target)
            let reading = try readLimit()
            guard reading.enabled, reading.limit == target else {
                throw PowerUIError.verificationFailed(
                    "read back limit=\(reading.limit)% enabled=\(reading.enabled)"
                )
            }
            return target
        } catch {
            try? disableLocked()
            throw error
        }
    }

    func disable() throws {
        let reading = try readLimit()
        guard reading.enabled else { return }

        try disableLocked()
        let after = try readLimit()
        guard !after.enabled else {
            throw PowerUIError.verificationFailed("the charge limit is still enabled")
        }
    }

    private func usableLimits() throws -> [Int] {
        if let cachedLimits {
            return cachedLimits
        }

        guard chargecap_powerui_is_supported() == 1 else {
            throw PowerUIError.unsupported
        }

        var buffer = [Int32](repeating: 0, count: 32)
        var count: Int32 = 0
        var errorPointer: UnsafeMutablePointer<CChar>?

        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            chargecap_powerui_copy_limits(
                pointer.baseAddress,
                Int32(pointer.count),
                &count,
                &errorPointer
            )
        }

        guard result == 0 else {
            throw PowerUIError.unavailable(takeError(errorPointer))
        }

        let limits = buffer.prefix(max(0, Int(count)))
            .map(Int.init)
            .filter { $0 > 0 && $0 < ChargeCapConstants.maximumCap }
            .sorted()

        guard !limits.isEmpty else {
            throw PowerUIError.noLimits
        }

        cachedLimits = limits
        return limits
    }

    private func readLimit() throws -> (limit: Int, enabled: Bool) {
        var limit: Int32 = 0
        var enabled: Int32 = 0
        var errorPointer: UnsafeMutablePointer<CChar>?

        let result = chargecap_powerui_read_limit(&limit, &enabled, &errorPointer)
        guard result == 0 else {
            throw PowerUIError.unavailable(takeError(errorPointer))
        }
        return (Int(limit), enabled != 0)
    }

    private func writeLimit(_ limit: Int) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = chargecap_powerui_set_limit(Int32(limit), &errorPointer)
        guard result == 0 else {
            throw PowerUIError.unavailable(takeError(errorPointer))
        }
    }

    private func disableLocked() throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = chargecap_powerui_disable(&errorPointer)
        guard result == 0 else {
            throw PowerUIError.unavailable(takeError(errorPointer))
        }
    }

    private func takeError(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "unknown error" }
        defer { chargecap_powerui_free_error(pointer) }
        return String(cString: pointer)
    }

    private func snap(_ requested: Int, to limits: [Int]) -> Int {
        let target = requested >= ChargeCapConstants.maximumCap
            ? ChargeCapConstants.defaultUpper
            : max(requested, limits.min() ?? ChargeCapConstants.defaultUpper)

        return limits.first(where: { $0 >= target }) ?? limits.max() ?? ChargeCapConstants.defaultUpper
    }
}
