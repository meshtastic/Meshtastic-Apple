// MARK: RadarSweepView
//
//  RadarSweepView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import SwiftUI

struct RadarSweepView: View {
	var isActive: Bool

	@State private var startDate = Date()

	/// Seconds for one full 360° rotation
	private let rotationDuration: Double = 15.0

	/// Number of expanding pulse rings
	private let pulseRingCount = 3

	/// Seconds for one pulse ring cycle (expand + fade)
	private let pulseCycleDuration: Double = 5.0

	var body: some View {
		if isActive {
			TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
				let elapsed = timeline.date.timeIntervalSince(startDate)
				let rotation = (elapsed / rotationDuration).truncatingRemainder(dividingBy: 1.0) * 360.0

				Canvas { context, size in
					let center = CGPoint(x: size.width / 2, y: size.height / 2)
					let radius = min(size.width, size.height) / 2

					// Outer ring
					var outerRing = Path()
					outerRing.addEllipse(in: CGRect(
						x: center.x - radius,
						y: center.y - radius,
						width: radius * 2,
						height: radius * 2
					))
context.stroke(outerRing, with: .color(.green.opacity(0.35)), lineWidth: 4)

					// Expanding pulse rings — staggered, radiate outward and fade
					for i in 0..<pulseRingCount {
						let offset = Double(i) / Double(pulseRingCount)
						let phase = (elapsed / pulseCycleDuration + offset).truncatingRemainder(dividingBy: 1.0)
						let ringRadius = radius * CGFloat(phase)
						let ringOpacity = 0.25 * (1.0 - phase) * (1.0 - phase)

						if ringRadius > 2 {
							var pulsePath = Path()
							pulsePath.addEllipse(in: CGRect(
								x: center.x - ringRadius,
								y: center.y - ringRadius,
								width: ringRadius * 2,
								height: ringRadius * 2
							))
							context.stroke(pulsePath, with: .color(.green.opacity(ringOpacity)), lineWidth: 4.5)
						}
					}

					// Crosshair lines
					var hLine = Path()
					hLine.move(to: CGPoint(x: center.x - radius, y: center.y))
					hLine.addLine(to: CGPoint(x: center.x + radius, y: center.y))
context.stroke(hLine, with: .color(.green.opacity(0.04)), lineWidth: 1.5)

					var vLine = Path()
					vLine.move(to: CGPoint(x: center.x, y: center.y - radius))
					vLine.addLine(to: CGPoint(x: center.x, y: center.y + radius))
context.stroke(vLine, with: .color(.green.opacity(0.04)), lineWidth: 1.5)

					// Sweep cone — 60° trailing fade
					let sweepAngle = Angle.degrees(rotation)
					let coneSpan = 60.0

					let cone = Path { p in
						p.move(to: center)
						p.addArc(center: center, radius: radius,
								 startAngle: sweepAngle - .degrees(coneSpan),
								 endAngle: sweepAngle, clockwise: false)
						p.closeSubpath()
					}
					context.fill(
						cone,
						with: .conicGradient(
							Gradient(colors: [
								.green.opacity(0.0),
								.green.opacity(0.0),
								.green.opacity(0.02),
								.green.opacity(0.06),
								.green.opacity(0.14),
								.green.opacity(0.28)
							]),
							center: center,
							angle: sweepAngle - .degrees(coneSpan)
						)
					)

					// Leading sweep line — glow
					let lineEnd = CGPoint(
						x: center.x + radius * cos(CGFloat(sweepAngle.radians)),
						y: center.y + radius * sin(CGFloat(sweepAngle.radians))
					)

					var glowLine = Path()
					glowLine.move(to: center)
					glowLine.addLine(to: lineEnd)
context.stroke(glowLine, with: .color(.green.opacity(0.20)), lineWidth: 9)

					// Leading sweep line — core
					var linePath = Path()
					linePath.move(to: center)
					linePath.addLine(to: lineEnd)
context.stroke(linePath, with: .color(.green.opacity(0.75)), lineWidth: 3)

					// Center dot with glow
					let glowSize: CGFloat = 10
					let glowRect = CGRect(x: center.x - glowSize / 2, y: center.y - glowSize / 2, width: glowSize, height: glowSize)
					context.fill(Path(ellipseIn: glowRect), with: .color(.green.opacity(0.15)))

					let dotSize: CGFloat = 4
					let dotRect = CGRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2, width: dotSize, height: dotSize)
					context.fill(Path(ellipseIn: dotRect), with: .color(.green.opacity(0.9)))
				}
			}
			.allowsHitTesting(false)
		}
	}
}
