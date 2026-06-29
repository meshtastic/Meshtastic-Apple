import SwiftUI
import MapKit
import CoreLocation

struct AnimatedNodePin: View, Equatable {
	let nodeColor: UIColor
	let shortName: String?
	let hasDetectionSensorMetrics: Bool
	let isOnline: Bool
	let calculatedDelay: Double
	let showsPulse: Bool
	private let swiftUIColor: Color

	init(nodeColor: UIColor, shortName: String?, hasDetectionSensorMetrics: Bool, isOnline: Bool, calculatedDelay: Double, showsPulse: Bool = true) {
		self.nodeColor = nodeColor
		self.shortName = shortName
		self.hasDetectionSensorMetrics = hasDetectionSensorMetrics
		self.isOnline = isOnline
		self.calculatedDelay = calculatedDelay
		self.showsPulse = showsPulse
		self.swiftUIColor = Color(nodeColor)
	}

	var body: some View {
		// The pulse is drawn as a *background* of the pin, never a sibling in a sizing ZStack, so it
		// stays concentric with the pin and can't change the hosted view's measured size (which the
		// MapKit annotation view re-reads on every reuse). That keeps the halo centered instead of
		// drifting above the node as it animates.
		pin
			.background {
				if isOnline && showsPulse {
					if #available(iOS 18, macOS 15, *) {
						PulsingCircle(nodeColor: nodeColor, calculatedDelay: calculatedDelay)
					}
				}
			}
	}

	@ViewBuilder private var pin: some View {
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

	static func == (lhs: AnimatedNodePin, rhs: AnimatedNodePin) -> Bool {
		return lhs.nodeColor == rhs.nodeColor &&
			   lhs.shortName == rhs.shortName &&
			   lhs.hasDetectionSensorMetrics == rhs.hasDetectionSensorMetrics &&
			   lhs.isOnline == rhs.isOnline &&
			   lhs.calculatedDelay == rhs.calculatedDelay &&
			   lhs.showsPulse == rhs.showsPulse
	}
}

#Preview {
	VStack(spacing: 20) {
		AnimatedNodePin(nodeColor: .systemBlue, shortName: "TN", hasDetectionSensorMetrics: false, isOnline: true, calculatedDelay: 0.0)
		AnimatedNodePin(nodeColor: .systemGreen, shortName: "AB", hasDetectionSensorMetrics: true, isOnline: true, calculatedDelay: 0.2)
		AnimatedNodePin(nodeColor: .systemRed, shortName: "XY", hasDetectionSensorMetrics: false, isOnline: false, calculatedDelay: 0.0)
	}
}

/// A softly breathing halo behind online nodes. Driven by an absolute-time `TimelineView` clock
/// rather than `@State` + `.onAppear` + `repeatForever`, so it never restarts or jumps when MapKit
/// recycles/reconfigures the annotation view (which it does constantly on pan/zoom/declutter). The
/// per-node `calculatedDelay` phase-shifts each node so they don't all pulse in unison.
struct PulsingCircle: View {
	let nodeColor: UIColor
	let calculatedDelay: Double

	/// Seconds for one full breath (out and back), matching the previous 1.2s-each-way feel.
	private let period: Double = 2.4

	var body: some View {
		TimelineView(.animation) { timeline in
			let elapsed = timeline.date.timeIntervalSinceReferenceDate + calculatedDelay
			let phase = elapsed.truncatingRemainder(dividingBy: period) / period
			// Smooth 0.9 -> 1.1 -> 0.9 ease via a cosine, continuous across cycles.
			let eased = (1 - cos(phase * 2 * .pi)) / 2
			let scale = 0.9 + 0.2 * eased
			Circle()
				.fill(Color(nodeColor.lighter()).opacity(0.3))
				.frame(width: 50, height: 50)
				.scaleEffect(scale)
		}
	}
}
