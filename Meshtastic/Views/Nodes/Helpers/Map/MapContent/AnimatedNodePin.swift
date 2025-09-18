import SwiftUI
import MapKit
import CoreLocation

struct AnimatedNodePin: View, Equatable {
	let nodeColor: UIColor
	let shortName: String?
	let hasDetectionSensorMetrics: Bool
	let isOnline: Bool
	let calculatedDelay: Double
	private let swiftUIColor: Color

	init(nodeColor: UIColor, shortName: String?, hasDetectionSensorMetrics: Bool, isOnline: Bool, calculatedDelay: Double) {
		self.nodeColor = nodeColor
		self.shortName = shortName
		self.hasDetectionSensorMetrics = hasDetectionSensorMetrics
		self.isOnline = isOnline
		self.calculatedDelay = calculatedDelay
		self.swiftUIColor = Color(nodeColor)
	}

	var body: some View {
		ZStack {
			// Pass the calculatedDelay to the PulsingCircle view
			if isOnline {
				PulsingCircle(nodeColor: nodeColor, calculatedDelay: calculatedDelay)
			}

			if hasDetectionSensorMetrics {
				Image(systemName: "sensor.fill")
					.symbolRenderingMode(.palette)
					.symbolEffect(.variableColor)
					.padding()
					.foregroundStyle(.white)
					.background(swiftUIColor)
					.clipShape(Circle())
			} else {
				CircleText(text: shortName ?? "?", color: swiftUIColor, circleSize: 40)
			}
		}
	}

	static func == (lhs: AnimatedNodePin, rhs: AnimatedNodePin) -> Bool {
		return lhs.nodeColor == rhs.nodeColor &&
			   lhs.shortName == rhs.shortName &&
			   lhs.hasDetectionSensorMetrics == rhs.hasDetectionSensorMetrics &&
			   lhs.isOnline == rhs.isOnline &&
			   lhs.calculatedDelay == rhs.calculatedDelay // Also check delay
	}
}

struct PulsingCircle: View {
	let nodeColor: UIColor
	let calculatedDelay: Double
	@State private var isPulsing = false

	var body: some View {
		Circle()
			.fill(Color(nodeColor.lighter()).opacity(0.4))
			.frame(width: 55, height: 55)
			.scaleEffect(isPulsing ? 1.2 : 0.8)
			.animation(
				.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(calculatedDelay),
				value: isPulsing
			)
			.onAppear {
				isPulsing = true
			}
	}
}
