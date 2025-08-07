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
	@State var isPopoverOpen = false
	
	let fontSize: CGFloat = 7.0
	var body: some View {
		Button( action: {
			self.isPopoverOpen.toggle()
		}) {
			VStack(spacing: 3.0) {
				HStack(spacing: 2.0) {
					Image(systemName: "arrow.up")
						.font(.system(size: fontSize))
					LEDIndicator(flash: $packetsSent, color: .green)
				}.frame(maxHeight: fontSize)
				HStack(spacing: 2.0) {
					Image(systemName: "arrow.down")
						.font(.system(size: fontSize))
					LEDIndicator(flash: $packetsReceived, color: .red)
				}.frame(maxHeight: fontSize)
			} }
		.popover(isPresented: self.$isPopoverOpen, content: {
			VStack(spacing: 0.5) {
				Text("Activity Lights")
					.font(.caption)
					.padding(20)
			}
			.presentationCompactAdaptation(.popover)
		})
	}
}

struct LEDIndicator: View {
	@Environment(\.colorScheme) var colorScheme
	@Binding var flash: Int
	let color: Color
	
	@State private var brightness: Double = 0.0

	var body: some View {
		Circle()
			.foregroundColor(color.opacity(brightness))
			.overlay(
				Circle()
					.stroke(colorScheme == .light ? Color.black : Color.white, lineWidth: 0.5)
			).onChange(of: flash) { _, _ in
				brightness = 1.0
				withAnimation(.easeOut(duration: 0.3)) {
					brightness = 0.0
				}
			}
	}
}
