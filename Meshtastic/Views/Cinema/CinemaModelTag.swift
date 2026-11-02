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
/// that node's live readings. While the connected radio's screen is live on the model, the card
/// also has a slider that makes the model up to five times its size, and the radio's buttons.
struct CinemaModelTag: View {
	let request: CinemaModelRequest
	/// The radio's screen is live on the model: show the zoom and the radio's buttons.
	var liveScreen = false
	/// How many times its real size the model stands at.
	var zoom: Float = 1
	var onZoom: (Float) -> Void = { _ in }
	var onInput: (DisplayInputEvent) -> Void = { _ in }
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
			if liveScreen {
				Divider()
				zoomSlider
				DeviceRemoteControl(send: onInput)
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

	/// From real size up to five times it, so the screen can be read from the seat.
	private var zoomSlider: some View {
		HStack(spacing: 8) {
			Slider(
				value: Binding(get: { Double(zoom) }, set: { onZoom(Float($0)) }),
				in: 1...Double(CinemaModelStandLayout.maximumZoom)
			) {
				Text("Size", comment: "Cinema: slider setting how many times its real size the model on the stand is shown at")
			} minimumValueLabel: {
				Image(systemName: "minus.magnifyingglass")
					.accessibilityLabel(String(localized: "Smaller", comment: "Cinema: the model size slider's low end, the model at its real size"))
			} maximumValueLabel: {
				Image(systemName: "plus.magnifyingglass")
					.accessibilityLabel(String(localized: "Larger", comment: "Cinema: the model size slider's high end, the model at five times its real size"))
			}
			.accessibilityValue(Text(verbatim: zoomText))
			Text(verbatim: zoomText)
				.font(.caption)
				.monospacedDigit()
				.fixedSize()
				.frame(minWidth: 36, alignment: .leading)
		}
	}

	private var zoomText: String {
		"\(zoom.formatted(.number.precision(.fractionLength(0...1))))×"
	}
}
#endif
