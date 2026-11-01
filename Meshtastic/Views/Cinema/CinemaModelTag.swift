//
//  CinemaModelTag.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/26/26.
//
#if os(visionOS)
import SwiftData
import SwiftUI

/// The card beside a model on the cinema's stand: the device, and when the model is of a node,
/// that node's live readings.
struct CinemaModelTag: View {
	let request: CinemaModelRequest
	let onClose: () -> Void
	@Environment(\.modelContext) private var context
	@State private var reading: CinemaNodeReading?

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .top, spacing: 10) {
				if let reading {
					CircleText(text: reading.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: reading.num))), circleSize: 40)
				}
				VStack(alignment: .leading, spacing: 2) {
					Text(reading?.longName ?? request.deviceName)
						.font(.headline)
					if reading != nil {
						Text(request.deviceName)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				Spacer(minLength: 8)
				Button(action: onClose) {
					Image(systemName: "xmark")
				}
				.buttonBorderShape(.circle)
				.accessibilityLabel(String(localized: "Put the model away", comment: "Cinema: button on the card beside a device model on the stand; takes the model away"))
			}
			if let reading {
				CinemaNodeReadings(reading: reading)
			}
		}
		.padding(16)
		.frame(width: 300, alignment: .leading)
		.glassBackgroundEffect()
		.task(id: request.nodeNum) {
			guard let nodeNum = request.nodeNum else {
				reading = nil
				return
			}
			while !Task.isCancelled {
				reading = CinemaNodeReading(nodeNum: nodeNum, context: context)
				try? await Task.sleep(for: .seconds(CinemaNodeReading.refresh))
			}
		}
	}
}
#endif
