//
//  CinemaNodeReadings.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
#if os(visionOS)
import SwiftData
import SwiftUI

/// A node's last heard, battery, signal and hops, for the cards beside a model on the stand and
/// beside a node out the lookout's windows.
struct CinemaNodeReadings: View {
	let reading: CinemaNodeReading

	var body: some View {
		Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
			GridRow {
				Label(String(localized: "Heard", comment: "Cinema: label on a node's card for when the node was last heard"), systemImage: "clock")
					.foregroundStyle(.secondary)
				if let lastHeard = reading.lastHeard {
					Text(lastHeard.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
				} else {
					Text(String(localized: "Never", comment: "Cinema: on a node's card, the node has never been heard"))
				}
			}
			if let battery = reading.batteryLevel {
				GridRow {
					Label(String(localized: "Battery", comment: "Cinema: label on a node's card for the node's battery"), systemImage: "battery.75percent")
						.foregroundStyle(.secondary)
					Text(battery > 100 ? String(localized: "Powered", comment: "Cinema: on a node's card, the node runs on external power") : "\(battery)%")
				}
			}
			if let snr = reading.snr {
				GridRow {
					Label(String(localized: "Signal", comment: "Cinema: label on a node's card for the node's signal"), systemImage: "cellularbars")
						.foregroundStyle(.secondary)
					Text("\(snr.formatted(.number.precision(.fractionLength(1)))) dB SNR")
				}
			}
			if let hops = reading.hopsAway {
				GridRow {
					Label(String(localized: "Hops", comment: "Cinema: label on a node's card for how many hops away the node is"), systemImage: "point.3.connected.trianglepath.dotted")
						.foregroundStyle(.secondary)
					Text(hops == 0 ? String(localized: "Direct", comment: "Cinema: on a node's card, the node is heard directly") : "\(hops)")
				}
			}
		}
		.font(.subheadline)
	}
}

/// One read of a node for a card in the cinema, kept as values so the card holds no store
/// objects. Cards read it every few seconds like the boards, not on every store change.
struct CinemaNodeReading {
	static let refresh: TimeInterval = 5

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
#endif
