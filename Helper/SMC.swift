import Darwin
import Foundation
import IOKit

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

enum SMCError: LocalizedError {
    case driverNotFound
    case failedToOpen
    case keyNotFound
    case notPrivileged
    case invalidDataSize(key: FourCharCode, expected: Int, actual: Int)
    case unknown(kIOReturn: kern_return_t, smcResult: UInt8)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .driverNotFound:
            return "AppleSMC is not available on this Mac."
        case .failedToOpen:
            return "Could not open the AppleSMC user client."
        case .keyNotFound:
            return "The firmware charge-limit keys are not present. A recent Apple Silicon Mac with macOS 26 or later is required."
        case .notPrivileged:
            return "SMC access was denied. ChargeCapHelper must be approved and running as root."
        case .invalidDataSize(let key, let expected, let actual):
            return "SMC key \(fourCCString(key)) has size \(actual); expected \(expected)."
        case .unknown(let ioReturn, let smcResult):
            return "SMC call failed (IOReturn \(ioReturn), result \(smcResult))."
        case .verificationFailed(let message):
            return "The firmware did not confirm the charge-limit change: \(message)"
        }
    }
}

extension FourCharCode {
    init(fromStaticString value: StaticString) {
        precondition(value.utf8CodeUnitCount == 4)
        self = value.withUTF8Buffer { buffer in
            (UInt32(buffer[0]) << 24) |
            (UInt32(buffer[1]) << 16) |
            (UInt32(buffer[2]) << 8) |
            UInt32(buffer[3])
        }
    }
}

func fourCCString(_ value: FourCharCode) -> String {
    let bytes = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

private struct SMCParamStruct {
    enum Selector: UInt8 {
        case handleYPCEvent = 2
        case readKey = 5
        case writeKey = 6
    }

    enum Result: UInt8 {
        case success = 0
        case keyNotFound = 132
    }

    struct Version {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

enum SMC {
    private static let lock = NSLock()
    private static var connection: io_connect_t = 0
    private static var isOpen = false

    static func readByte(_ key: FourCharCode) throws -> UInt8 {
        try readBytes(key).0
    }

    static func readUInt32LittleEndian(_ key: FourCharCode) throws -> UInt32 {
        let bytes = try readBytes(key)
        return UInt32(bytes.3) << 24 |
            UInt32(bytes.2) << 16 |
            UInt32(bytes.1) << 8 |
            UInt32(bytes.0)
    }

    static func writeByte(_ key: FourCharCode, value: UInt8) throws {
        lock.lock()
        defer { lock.unlock() }
        try openIfNeededLocked()
        try validateSizeLocked(key, expected: 1)

        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = 1
        input.data8 = SMCParamStruct.Selector.writeKey.rawValue
        input.bytes.0 = value
        _ = try callLocked(&input)
    }

    static func writeUInt32LittleEndian(_ key: FourCharCode, value: UInt32) throws {
        lock.lock()
        defer { lock.unlock() }
        try openIfNeededLocked()
        try validateSizeLocked(key, expected: 4)

        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = 4
        input.data8 = SMCParamStruct.Selector.writeKey.rawValue
        input.bytes.0 = UInt8(value & 0xff)
        input.bytes.1 = UInt8((value >> 8) & 0xff)
        input.bytes.2 = UInt8((value >> 16) & 0xff)
        input.bytes.3 = UInt8((value >> 24) & 0xff)
        _ = try callLocked(&input)
    }

    private static func readBytes(_ key: FourCharCode) throws -> SMCBytes {
        lock.lock()
        defer { lock.unlock() }
        try openIfNeededLocked()
        try validateSizeLocked(key, expected: nil)

        var input = SMCParamStruct()
        input.key = key
        input.data8 = SMCParamStruct.Selector.readKey.rawValue
        input.keyInfo.dataSize = 32
        let output = try callLocked(&input)
        return output.bytes
    }

    private static func validateSizeLocked(_ key: FourCharCode, expected: Int?) throws {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = SMCParamStruct.Selector.readKey.rawValue
        input.keyInfo.dataSize = 32
        let output = try callLocked(&input)
        let actual = Int(output.keyInfo.dataSize)

        if let expected, actual != 0, actual != expected {
            throw SMCError.invalidDataSize(key: key, expected: expected, actual: actual)
        }
    }

    private static func openIfNeededLocked() throws {
        guard !isOpen else { return }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.failedToOpen }
        isOpen = true
    }

    private static func closeLocked() {
        if isOpen {
            IOServiceClose(connection)
            connection = 0
            isOpen = false
        }
    }

    @discardableResult
    private static func callLocked(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct must be 80 bytes")

        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCParamStruct.Selector.handleYPCEvent.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )

        switch (result, output.result) {
        case (kIOReturnSuccess, SMCParamStruct.Result.success.rawValue):
            return output
        case (kIOReturnSuccess, SMCParamStruct.Result.keyNotFound.rawValue):
            throw SMCError.keyNotFound
        case (kIOReturnNotPrivileged, _):
            closeLocked()
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(kIOReturn: result, smcResult: output.result)
        }
    }
}
