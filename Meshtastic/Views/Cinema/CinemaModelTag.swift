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
/// that node's live readings. Read every few seconds like the boards, not on every store change.
struct CinemaModelTag: View {
	let request: CinemaModelRequest
	let onClose: () -> Void
	@Environment(\.modelContext) private var context
	@State private var reading: Reading?

	private static let refresh: TimeInterval = 5

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
				readings(reading)
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
				reading = Reading(nodeNum: nodeNum, context: context)
				try? await Task.sleep(for: .seconds(Self.refresh))
			}
		}
	}

	private func readings(_ reading: Reading) -> some View {
		Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
			GridRow {
				Label(String(localized: "Heard", comment: "Cinema: label on the model card for when the node was last heard"), systemImage: "clock")
					.foregroundStyle(.secondary)
				if let lastHeard = reading.lastHeard {
					Text(lastHeard.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
				} else {
					Text(String(localized: "Never", comment: "Cinema: on the model card, the node has never been heard"))
				}
			}
			if let battery = reading.batteryLevel {
				GridRow {
					Label(String(localized: "Battery", comment: "Cinema: label on the model card for the node's battery"), systemImage: "battery.75percent")
						.foregroundStyle(.secondary)
					Text(battery > 100 ? String(localized: "Powered", comment: "Cinema: on the model card, the node runs on external power") : "\(battery)%")
				}
			}
			if let snr = reading.snr {
				GridRow {
					Label(String(localized: "Signal", comment: "Cinema: label on the model card for the node's signal"), systemImage: "cellularbars")
						.foregroundStyle(.secondary)
					Text("\(snr.formatted(.number.precision(.fractionLength(1)))) dB SNR")
				}
			}
			if let hops = reading.hopsAway {
				GridRow {
					Label(String(localized: "Hops", comment: "Cinema: label on the model card for how many hops away the node is"), systemImage: "point.3.connected.trianglepath.dotted")
						.foregroundStyle(.secondary)
					Text(hops == 0 ? String(localized: "Direct", comment: "Cinema: on the model card, the node is heard directly") : "\(hops)")
				}
			}
		}
		.font(.subheadline)
	}

	/// One read of the node, kept as values so the card holds no store objects.
	private struct Reading {
		let num: Int64
		let shortName: String
		let longName: String
		let lastHeard: Date?
		let batteryLevel: Int32?
		let snr: Float?
		let hopsAway: Int32?

		@MainActor init?(nodeNum: Int64, context: ModelContext) {
			guard let node = getNodeInfo(id: nodeNum, context: context) else { return nil }
			let user = node.liveUser
			num = node.num
			shortName = user?.shortName ?? String(format: "%04x", UInt32(truncatingIfNeeded: node.num) & 0xffff)
			longName = user?.longName ?? "!" + String(format: "%08x", UInt32(truncatingIfNeeded: node.num))
			lastHeard = node.lastHeard
			batteryLevel = node.latestDeviceMetrics?.batteryLevel
			// Signal only for nodes heard directly, and never over MQTT, as on the boards.
			snr = node.snr != 0 && !node.viaMqtt && node.hopsAway == 0 ? node.snr : nil
			hopsAway = node.viaMqtt ? nil : node.hopsAway
		}
	}
}
#endif
