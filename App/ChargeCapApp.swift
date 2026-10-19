import SwiftUI

@main
struct ChargeCapApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ChargeCapMenuView(model: model)
        } label: {
            Label("\(model.battery.percent)%", systemImage: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct ChargeCapMenuView: View {
    @ObservedObject var model: AppModel
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            capControls
            helperSection
            Divider()
            controlCenterSection
            Divider()
            HStack {
                Spacer()
                Button("Quit ChargeCap") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 330)
        .alert("Remove ChargeCapHelper?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Restore Charging and Remove", role: .destructive) {
                model.disableAndRemoveHelper()
            }
        } message: {
            Text("This turns the charge limit off, restores normal charging, and unregisters the background helper.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.menuBarSymbol)
                .font(.system(size: 30))
                .foregroundStyle(model.state.active ? .green : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.battery.percent)% battery")
                    .font(.headline)
                Text(batteryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var batteryDetail: String {
        if model.battery.isCharging {
            return "Charging"
        }
        if model.battery.isPluggedIn {
            return "Plugged in"
        }
        return "On battery"
    }

    private var capControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { model.state.active },
                set: { model.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Charge cap")
                    Text(model.state.active ? "Stops at \(model.state.upper)%" : "Charge limit is off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!model.state.supported || model.isBusy)

            HStack {
                Text("Limit")
                Spacer()
                Picker("Limit", selection: Binding(
                    get: { model.selectedLimit },
                    set: { model.setLimit($0) }
                )) {
                    ForEach(model.limitOptions, id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
                .disabled(!model.helperIsReady || model.isBusy)
            }

            if let detail = model.backendDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = model.state.error ?? model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var helperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(model.helperIsReady && model.state.supported ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(model.helperStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") {
                    Task { await model.refreshAll() }
                }
                .buttonStyle(.link)
            }

            if !model.isInstalledInApplications {
                Text("Move ChargeCap to /Applications, then reopen it to install the privileged helper.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.helperStatus == .requiresApproval {
                Button("Approve Helper in Login Items") {
                    model.openLoginItemsSettings()
                }
            } else if model.helperStatus == .notRegistered || model.helperStatus == .notFound {
                Button("Install Helper") {
                    model.registerHelper()
                }
            } else if model.helperStatus == .enabled && !model.state.supported {
                Button("Open Login Items") {
                    model.openLoginItemsSettings()
                }
            }

            if model.helperIsReady {
                Button("Restore Charging and Remove Helper…", role: .destructive) {
                    confirmingRemoval = true
                }
                .font(.caption)
            }
        }
    }

    private var controlCenterSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Control Center")
                .font(.caption.weight(.semibold))
            Text("Open Control Center, choose Edit Controls, and add the ChargeCap switch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Control Center Settings") {
                model.openControlCenterSettings()
            }
            .font(.caption)
        }
    }
}
