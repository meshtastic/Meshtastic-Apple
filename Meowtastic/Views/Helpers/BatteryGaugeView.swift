import SwiftUI
import Charts

struct BatteryGaugeView: View {
	@ObservedObject
	var node: NodeInfoEntity

	private let minValue = 0.0
	private let maxValue = 100.00
	private let gaugeGradient = Gradient(colors: [.red, .orange, .green])

	var body: some View {
		if let telemetries = node.telemetries {
			let deviceMetrics = telemetries.filtered(
				using: NSPredicate(format: "metricsType == 0")
			)
			let mostRecent = deviceMetrics.lastObject as? TelemetryEntity
			let batteryLevel = Double(mostRecent?.batteryLevel ?? 0)

			VStack {
				if batteryLevel > 100.0 {
					Image(systemName: "powerplug")
						.font(.largeTitle)
						.foregroundColor(.accentColor)
						.symbolRenderingMode(.hierarchical)
				} else {
					Gauge(value: batteryLevel, in: minValue...maxValue) {
						if batteryLevel < 10 {
							Label("Battery Level %", systemImage: "battery.0")
						} else if batteryLevel < 25 {
							Label("Battery Level %", systemImage: "battery.25")
						} else if batteryLevel < 50 {
							Label("Battery Level %", systemImage: "battery.50")
						} else if batteryLevel < 75 {
							Label("Battery Level %", systemImage: "battery.75")
						} else if batteryLevel <= 99 {
							Label("Battery Level %", systemImage: "battery.100")
						} else {
							Label("Battery Level %", systemImage: "battery.100.bolt")
						}
					} currentValueLabel: {
						if let voltage = mostRecent?.voltage, voltage > 0.00 {
							let voltageFormatted = String(format: "%.2f", voltage) + "V"

							Text(voltageFormatted)
								.font(.footnote)
								.lineLimit(1)
								.fixedSize()
								.minimumScaleFactor(0.5)
								.padding(4)
						}
						else {
							EmptyView()
						}
					}
					.tint(gaugeGradient)
					.gaugeStyle(.accessoryCircular)
				}
			}
		}
		else {
			EmptyView()
		}
	}
}
