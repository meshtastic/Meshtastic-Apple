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
	@State private var isPopoverOpen = false
	
	let fontSize: CGFloat = 7.0
	var body: some View {
		Button( action: {
			if !isPopoverOpen && accessoryManager.isConnected {
				Task {
					//TODO: replace with a heartbeat when the heartbeat works
					try await Task.sleep(for: .seconds(0.5)) // little delay for user affordance
					try await accessoryManager.requestDeviceMetadata()
				}
			}
			self.isPopoverOpen.toggle()
		}) {
			VStack(spacing: 3.0) {
				HStack(spacing: 2.0) {
					Image(systemName: "arrow.up")
						.font(.system(size: fontSize))
					LEDIndicator(flash: $accessoryManager.packetsSent, color: .green)
				}.frame(maxHeight: fontSize)
				HStack(spacing: 2.0) {
					Image(systemName: "arrow.down")
						.font(.system(size: fontSize))
					LEDIndicator(flash: $accessoryManager.packetsReceived, color: .red)
				}.frame(maxHeight: fontSize)
			}
			.contentShape(Rectangle()) // Make sure the whole thing is tappable
			.popover(isPresented: self.$isPopoverOpen,
					 attachmentAnchor: .rect(.bounds),
					 arrowEdge: .top) {
				Button(action: {
					self.isPopoverOpen = false
				}) {
					VStack(spacing: 0.5) {
						Text("Activity Lights")
							.font(.caption)
							.bold()
							.padding(2.0)
						Divider()
						Text("Packet Count")
							.font(.caption2)
							.padding(2.0)
						
						VStack(alignment: .leading) {
							HStack(spacing: 3.0) {
								HStack(spacing: 2.0) {
									LEDIndicator(flash: $accessoryManager.packetsSent, color: .green)
										.frame(maxHeight: fontSize)
									Image(systemName: "arrow.up")
										.font(.system(size: fontSize))
								}
								Text("To Radio (TX): \(accessoryManager.packetsSent)")
									.font(.caption2)
								Spacer()
							}
							HStack(spacing: 3.0) {
								HStack(spacing: 2.0) {
									LEDIndicator(flash: $accessoryManager.packetsReceived, color: .red)
										.frame(maxHeight: fontSize)
									Image(systemName: "arrow.down")
										.font(.system(size: fontSize))
								}
								Text("From Radio (RX): \(accessoryManager.packetsReceived)")
									.font(.caption2)
								Spacer()
							}
						}.padding(2.0)
					}.padding(10)
					.contentShape(Rectangle()) // Make sure the whole thing is tappable
				}.buttonStyle(.plain)
				.presentationCompactAdaptation(.popover)
			}
		}.buttonStyle(.borderless)
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
