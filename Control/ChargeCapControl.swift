import AppIntents
import SwiftUI
import WidgetKit

@main
struct ChargeCapControlBundle: WidgetBundle {
    var body: some Widget {
        ChargeCapControl()
    }
}

struct ChargeCapControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: ChargeCapConstants.controlKind,
            provider: Provider()
        ) { isOn in
            ControlWidgetToggle(
                "Charge Cap",
                isOn: isOn,
                action: ToggleChargeCapIntent()
            ) { isOn in
                Label(isOn ? "Capped" : "Off", systemImage: "battery.75percent")
                    .controlWidgetActionHint(isOn ? "Allow normal charging" : "Enable charge cap")
            }
            .tint(.green)
        }
        .displayName("Charge Cap")
        .description("Limit battery charging to your configured percentage.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            try await HelperClient.shared.fetchState().active
        }
    }
}

struct ToggleChargeCapIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Charge Cap"

    @Parameter(title: "Charge Cap")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let current = try await HelperClient.shared.fetchState()
        guard current.supported else {
            throw HelperClientError.helperUnavailable(current.error)
        }

        let upper = (ChargeCapConstants.minimumCap...ChargeCapConstants.maximumCap).contains(current.upper)
            ? current.upper
            : ChargeCapConstants.defaultUpper
        let lower = current.lower > 0 && current.lower < upper
            ? current.lower
            : ChargeCapConfiguration.forUpper(upper).lower

        _ = try await HelperClient.shared.apply(enabled: value, upper: upper, lower: lower)
        ControlCenter.shared.reloadControls(ofKind: ChargeCapConstants.controlKind)
        return .result()
    }
}
