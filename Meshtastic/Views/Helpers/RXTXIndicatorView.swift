//
//  RXTXIndicatorView.swift
//  Meshtastic
//
//  Created by jake on 8/5/25.
//

import Foundation
import SwiftUI
import Combine

struct RXTXIndicatorWidget: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Binding var packetsSent: Int
	@Binding var packetsReceived: Int
	
	let fontSize: CGFloat = 7.0
	var body: some View {
		VStack (spacing: 3.0) {
			HStack (spacing: 2.0) {
				Image(systemName:"arrow.up")
					.font(.system(size: fontSize))
				LEDIndicator(flash: $packetsSent, color: .green)
			}.frame(maxHeight: fontSize)
			HStack (spacing: 2.0) {
				Image(systemName:"arrow.down")
					.font(.system(size: fontSize))
				LEDIndicator(flash: $packetsReceived, color: .red)
			}.frame(maxHeight: fontSize)
		}
	}
}

struct LEDIndicator: View {
	@Binding var flash: Int
	let color: Color
	
	@State private var brightness: Double = 0.0

	var body: some View {
		Circle()
			.foregroundColor(color.opacity(brightness))
			.overlay(
				Circle()
					.stroke(Color.black, lineWidth: 0.5)
			).onChange(of: flash) { _, _ in
				brightness = 1.0
				withAnimation(.easeOut(duration: 0.3)) {
					brightness = 0.0
				}
			}
	}
}
