import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = ChargeCapState.unavailable
    @Published private(set) var battery = BatterySnapshot.unknown
    @Published private(set) var helperStatus = SMAppService.daemon(
        plistName: ChargeCapConstants.daemonPlistName
    ).status
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var selectedLimit: Int {
        didSet {
            UserDefaults.standard.set(selectedLimit, forKey: Self.selectedLimitKey)
        }
    }

    private static let selectedLimitKey = "ChargeCap.selectedLimit"
    private var timer: Timer?

    init() {
        let storedLimit = UserDefaults.standard.integer(forKey: Self.selectedLimitKey)
        let initialLimit = storedLimit == 0 ? ChargeCapConstants.defaultUpper : storedLimit
        selectedLimit = ChargeCapConfiguration.forUpper(initialLimit).upper
        battery = BatteryReader.read()
        startPolling()
        Task { await start() }
    }

    var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    var helperIsReady: Bool {
        helperStatus == .enabled
    }

    var helperStatusText: String {
        switch helperStatus {
        case .enabled:
            return state.supported ? "Helper active" : "Helper needs attention"
        case .requiresApproval:
            return "Waiting for approval"
        case .notRegistered:
            return "Helper not installed"
        case .notFound:
            return "Helper missing from app bundle"
        @unknown default:
            return "Unknown helper status"
        }
    }

    var menuBarSymbol: String {
        if state.active {
            return "battery.75percent"
        }
        if battery.isCharging {
            return "battery.100percent.bolt"
        }
        if battery.isPluggedIn {
            return "battery.100percent"
        }
        return battery.percent <= 20 ? "battery.25percent" : "battery.50percent"
    }

    func start() async {
        if isInstalledInApplications {
            registerHelperIfNeeded()
        }
        await refreshAll()
    }

    func refreshAll() async {
        battery = BatteryReader.read()
        helperStatus = SMAppService.daemon(plistName: ChargeCapConstants.daemonPlistName).status

        guard helperStatus == .enabled else {
            state = ChargeCapState(
                active: false,
                supported: false,
                upper: selectedLimit,
                lower: ChargeCapConfiguration.forUpper(selectedLimit).lower,
                rawActivation: 0,
                error: nil
            )
            return
        }

        do {
            let refreshed = try await HelperClient.shared.fetchState()
            state = refreshed
            if refreshed.supported, !refreshed.active {
                selectedLimit = refreshed.upper
                state.upper = selectedLimit
            }
        } catch {
            state = ChargeCapState(
                active: false,
                supported: false,
                upper: selectedLimit,
                lower: ChargeCapConfiguration.forUpper(selectedLimit).lower,
                rawActivation: 0,
                error: error.localizedDescription
            )
        }
    }

    func registerHelper() {
        let service = SMAppService.daemon(plistName: ChargeCapConstants.daemonPlistName)
        do {
            switch service.status {
            case .notRegistered:
                try service.register()
            case .notFound:
                try? service.unregister()
                try service.register()
            case .requiresApproval, .enabled:
                break
            @unknown default:
                try service.register()
            }
            helperStatus = service.status
            if helperStatus == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            errorMessage = "Could not register ChargeCapHelper: \(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openControlCenterSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    func setEnabled(_ enabled: Bool) {
        guard !isBusy else { return }
        let cap = ChargeCapConfiguration.forUpper(selectedLimit)
        isBusy = true
        errorMessage = nil

        Task {
            do {
                let updated = try await HelperClient.shared.apply(
                    enabled: enabled,
                    upper: cap.upper,
                    lower: cap.lower
                )
                state = updated
                errorMessage = updated.error
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
            await refreshAll()
        }
    }

    func setLimit(_ upper: Int) {
        let cap = ChargeCapConfiguration.forUpper(upper)
        selectedLimit = cap.upper

        guard helperStatus == .enabled, !isBusy else { return }
        isBusy = true
        errorMessage = nil

        Task {
            do {
                let updated = try await HelperClient.shared.apply(
                    enabled: state.active,
                    upper: cap.upper,
                    lower: cap.lower
                )
                state = updated
                errorMessage = updated.error
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
            await refreshAll()
        }
    }

    func disableAndRemoveHelper() {
        isBusy = true
        errorMessage = nil

        Task {
            do {
                let cap = ChargeCapConfiguration.forUpper(selectedLimit)
                _ = try await HelperClient.shared.apply(enabled: false, upper: cap.upper, lower: cap.lower)
            } catch {
                errorMessage = "Could not restore normal charging before removing the helper: \(error.localizedDescription)"
                isBusy = false
                return
            }

            do {
                try await SMAppService.daemon(plistName: ChargeCapConstants.daemonPlistName).unregister()
                helperStatus = SMAppService.daemon(plistName: ChargeCapConstants.daemonPlistName).status
            } catch {
                errorMessage = "Charging was restored, but the helper could not be removed: \(error.localizedDescription)"
            }
            isBusy = false
            await refreshAll()
        }
    }

    private func registerHelperIfNeeded() {
        let service = SMAppService.daemon(plistName: ChargeCapConstants.daemonPlistName)
        switch service.status {
        case .notRegistered, .notFound:
            registerHelper()
        case .requiresApproval, .enabled:
            break
        @unknown default:
            break
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
    }
}
