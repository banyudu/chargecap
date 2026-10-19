import Darwin
import Foundation

private func printState(_ state: ChargeCapState) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(state),
       let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

private func runCommandLine(_ arguments: [String]) -> Int32 {
    let firmware = FirmwareChargeLimit()
    let store = ChargeCapConfigStore()
    var configuration = store.load()

    do {
        switch arguments.dropFirst().first {
        case "probe", "state":
            printState(firmware.readState(configuration: configuration))
            return 0
        case "set":
            guard arguments.count >= 3, let upper = Int(arguments[2]) else {
                fputs("usage: ChargeCapHelper set <upper-percent>\n", stderr)
                return 64
            }
            let requested = ChargeCapConfiguration.forUpper(upper)
            try firmware.setLimit(upper: requested.upper, lower: requested.lower)
            configuration = requested
            store.save(configuration)
            printState(firmware.readState(configuration: configuration))
            return 0
        case "off":
            try firmware.disableLimit()
            printState(firmware.readState(configuration: configuration))
            return 0
        default:
            fputs("usage: ChargeCapHelper [state|probe|set <upper-percent>|off]\n", stderr)
            return 64
        }
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

if CommandLine.arguments.count > 1 {
    exit(runCommandLine(CommandLine.arguments))
}

let listener = NSXPCListener(machServiceName: ChargeCapConstants.machServiceName)
let delegate = ChargeCapDaemonDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
