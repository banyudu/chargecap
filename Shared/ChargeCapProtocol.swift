import Foundation

enum ChargeCapConstants {
    static let appBundleID = "com.banyudu.chargecap"
    static let controlBundleID = "com.banyudu.chargecap.control"
    static let helperBundleID = "com.banyudu.chargecap.helper"
    static let machServiceName = "com.banyudu.chargecap.helper"
    static let daemonPlistName = "com.banyudu.chargecap.helper.plist"
    static let controlKind = "ChargeCapControl"
    static let teamID = "RYLS8UDY5D"

    static let defaultUpper = 80
    static let defaultLower = 75
    static let minimumCap = 50
    static let minimumLower = 40
    static let maximumCap = 100
    static let hysteresis = 5

    static let helperRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and " +
        "identifier \"\(helperBundleID)\""

    static let clientRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and " +
        "(identifier \"\(appBundleID)\" or identifier \"\(controlBundleID)\")"
}

enum ChargeCapBackend: String, Codable, Equatable {
    case firmware
    case native
    case unavailable
}

struct ChargeCapState: Codable, Equatable {
    var active: Bool
    var supported: Bool
    var upper: Int
    var lower: Int
    var rawActivation: Int
    var backend: ChargeCapBackend
    var availableLimits: [Int]
    var error: String?

    static let unavailable = ChargeCapState(
        active: false,
        supported: false,
        upper: ChargeCapConstants.defaultUpper,
        lower: ChargeCapConstants.defaultLower,
        rawActivation: 0,
        backend: .unavailable,
        availableLimits: [],
        error: nil
    )
}

struct ChargeCapConfiguration: Codable, Equatable {
    var upper: Int
    var lower: Int

    static let `default` = ChargeCapConfiguration(
        upper: ChargeCapConstants.defaultUpper,
        lower: ChargeCapConstants.defaultLower
    )

    func sanitized() -> ChargeCapConfiguration {
        let safeUpper = min(max(upper, ChargeCapConstants.minimumCap), ChargeCapConstants.maximumCap)
        let safeLower = min(max(lower, ChargeCapConstants.minimumLower), safeUpper - 1)
        return ChargeCapConfiguration(upper: safeUpper, lower: safeLower)
    }

    static func forUpper(_ upper: Int) -> ChargeCapConfiguration {
        let safeUpper = min(max(upper, ChargeCapConstants.minimumCap), ChargeCapConstants.maximumCap)
        let lower = max(ChargeCapConstants.minimumLower, safeUpper - ChargeCapConstants.hysteresis)
        return ChargeCapConfiguration(upper: safeUpper, lower: lower)
    }
}

@objc(ChargeCapHelperXPCProtocol)
protocol ChargeCapHelperXPCProtocol {
    func fetchState(withReply reply: @escaping (NSData?, NSString?) -> Void)
    func apply(enabled: Bool, upper: Int, lower: Int, withReply reply: @escaping (NSData?, NSString?) -> Void)
}
