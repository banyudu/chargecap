import Foundation

final class ChargeCapConfigStore {
    private let fileURL: URL

    init() {
        fileURL = URL(fileURLWithPath: "/Library/Application Support/ChargeCap/config.json")
    }

    func load() -> ChargeCapConfiguration {
        guard let data = try? Data(contentsOf: fileURL),
              let configuration = try? JSONDecoder().decode(ChargeCapConfiguration.self, from: data) else {
            return .default
        }
        return configuration.sanitized()
    }

    func save(_ configuration: ChargeCapConfiguration) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ChargeCapHelper could not persist configuration: \(error.localizedDescription)")
        }
    }
}
