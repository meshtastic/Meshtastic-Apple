//
//  AnimatedPin.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/15/25.
//

import SwiftUI
import MapKit
import CoreLocation

struct AnimatedNodePin: View {
	// Properties for the view to render
	let nodeColor: UIColor
	let shortName: String?
	let hasDetectionSensorMetrics: Bool
	let isOnline: Bool
	
	// Properties for the animation
	let calculatedDelay: Double
	
	@State private var isPulsing: Bool = false
	
	var body: some View {
		let swiftUIColor = Color(nodeColor)
		
		ZStack {
			if isOnline {
				Circle()
					.fill(Color(nodeColor.lighter()).opacity(0.4).shadow(.drop(color: Color(nodeColor).isLight() ? .black : .white, radius: 5)))
					.frame(width: 55, height: 55)
					.scaleEffect(isPulsing ? 1.2 : 0.8)
					.animation(
						.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(calculatedDelay),
						value: isPulsing
					)
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
		.onAppear {
			isPulsing = isOnline
		}
		.onChange(of: isOnline) {_, newIsOnline in
			isPulsing = newIsOnline
		}
	}
}
