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

	@State private var rotation: Double = 0

	var body: some View {
		if isActive {
			Canvas { context, size in
				let center = CGPoint(x: size.width / 2, y: size.height / 2)
				let radius = min(size.width, size.height) / 2

				// Draw sweep gradient
				let sweepAngle = Angle.degrees(rotation)
				let path = Path { p in
					p.move(to: center)
					p.addArc(
						center: center,
						radius: radius,
						startAngle: sweepAngle - .degrees(45),
						endAngle: sweepAngle,
						clockwise: false
					)
					p.closeSubpath()
				}

				context.fill(
					path,
					with: .linearGradient(
						Gradient(colors: [
							.green.opacity(0.0),
							.green.opacity(0.15),
							.green.opacity(0.3)
						]),
						startPoint: CGPoint(
							x: center.x + radius * cos(CGFloat((sweepAngle - .degrees(45)).radians)),
							y: center.y + radius * sin(CGFloat((sweepAngle - .degrees(45)).radians))
						),
						endPoint: CGPoint(
							x: center.x + radius * cos(CGFloat(sweepAngle.radians)),
							y: center.y + radius * sin(CGFloat(sweepAngle.radians))
						)
					)
				)

				// Draw sweep line
				let lineEnd = CGPoint(
					x: center.x + radius * cos(CGFloat(sweepAngle.radians)),
					y: center.y + radius * sin(CGFloat(sweepAngle.radians))
				)
				var linePath = Path()
				linePath.move(to: center)
				linePath.addLine(to: lineEnd)
				context.stroke(linePath, with: .color(.green.opacity(0.5)), lineWidth: 1.5)
			}
			.allowsHitTesting(false)
			.onAppear {
				withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
					rotation = 360
				}
			}
			.onDisappear {
				rotation = 0
			}
		}
	}
}
