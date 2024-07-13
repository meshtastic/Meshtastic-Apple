import SwiftUI
import Charts

struct BatteryGaugeView: View {
	@ObservedObject
	var node: NodeInfoEntity

	private let withLabels: Bool
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

			HStack {
				if withLabels {
					Image(systemName: "battery.75percent")
						.font(.body)
						.frame(width: 32)
				}

				Gauge(value: min(batteryLevel, 100), in: minValue...maxValue) { }
					.gaugeStyle(.accessoryLinear)
					.tint(gaugeGradient)

				if withLabels {
					if let voltage = mostRecent?.voltage, voltage > 0 {
						let voltageFormatted = String(format: "%.2f", voltage) + "V"
						
						Text(voltageFormatted)
							.font(.footnote)
							.lineLimit(1)
							.fixedSize(horizontal: true, vertical: false)
							.minimumScaleFactor(0.5)
							.padding(4)
					}
					else {
						let socFormatted = String(format: "%.1f", batteryLevel) + "%"
						
						Text(socFormatted)
							.font(.footnote)
							.lineLimit(1)
							.fixedSize(horizontal: true, vertical: false)
							.minimumScaleFactor(0.5)
							.padding(4)
					}
				}
			}
		}
		else {
			EmptyView()
		}
	}

	init(
		node: NodeInfoEntity,
		withLabels: Bool = false
	) {
		self.node = node
		self.withLabels = withLabels
	}
}
