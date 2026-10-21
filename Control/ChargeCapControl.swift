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
        ) { value in
            ControlWidgetToggle(
                "Charge Cap",
                isOn: value.isOn,
                action: ToggleChargeCapIntent()
            ) { isOn in
                Label {
                    Text(isOn ? "Capped" : "Off")
                } icon: {
                    Text("\(value.upper)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .controlWidgetActionHint(isOn ? "Allow normal charging" : "Enable charge cap")
            }
            .tint(.green)
        }
        .displayName("Charge Cap")
        .description("Limit battery charging to your configured percentage.")
    }

    struct Value: Equatable, Sendable {
        var isOn: Bool
        var upper: Int
    }

    struct Provider: ControlValueProvider {
        var previewValue: Value {
            Value(isOn: true, upper: ChargeCapConstants.defaultUpper)
        }

        func currentValue() async throws -> Value {
            guard let state = try? await HelperClient.shared.fetchState() else {
                return Value(isOn: false, upper: ChargeCapConstants.defaultUpper)
            }

            return Value(
                isOn: state.active,
                upper: state.supported ? state.upper : ChargeCapConstants.defaultUpper
            )
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
