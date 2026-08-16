import NerunaCore
import SwiftUI

struct SettingsView: View {
    @Environment(SleepPreventionController.self) private var controller

    var body: some View {
        Form {
            Section("電池") {
                Toggle(
                    "残量が少ないとき寝る",
                    isOn: batteryGuardBinding
                )
                Stepper(value: batteryThresholdBinding, in: AwakeConfiguration.batteryPercentRange) {
                    Text("\(controller.configuration.batteryThresholdPercent ?? AwakeConfiguration.defaultBatteryThresholdPercent)% を下回ったら")
                }
                .disabled(controller.configuration.batteryThresholdPercent == nil)
            }

            Section("時間") {
                Toggle("時間がたったら寝る", isOn: durationGuardBinding)
                Stepper(value: durationHoursBinding, in: AwakeConfiguration.durationHoursRange) {
                    Text("\(controller.configuration.durationLimitHours ?? 4) 時間たったら")
                }
                .disabled(controller.configuration.durationLimitSeconds == nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 240)
        .padding()
    }

    private var batteryGuardBinding: Binding<Bool> {
        Binding(
            get: { controller.configuration.batteryThresholdPercent != nil },
            set: { enabled in
                Task {
                    await controller.setBatteryThreshold(
                        enabled ? (controller.configuration.batteryThresholdPercent ?? AwakeConfiguration.defaultBatteryThresholdPercent) : nil
                    )
                }
            }
        )
    }

    private var batteryThresholdBinding: Binding<Int> {
        Binding(
            get: {
                controller.configuration.batteryThresholdPercent
                    ?? AwakeConfiguration.defaultBatteryThresholdPercent
            },
            set: { value in
                Task {
                    await controller.setBatteryThreshold(value)
                }
            }
        )
    }

    private var durationGuardBinding: Binding<Bool> {
        Binding(
            get: { controller.configuration.durationLimitSeconds != nil },
            set: { enabled in
                Task {
                    await controller.setDurationHours(enabled ? (controller.configuration.durationLimitHours ?? 4) : nil)
                }
            }
        )
    }

    private var durationHoursBinding: Binding<Int> {
        Binding(
            get: { controller.configuration.durationLimitHours ?? 4 },
            set: { value in
                Task {
                    await controller.setDurationHours(value)
                }
            }
        )
    }
}
