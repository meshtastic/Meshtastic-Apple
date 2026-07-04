// MARK: DiscoveryBeaconsView
//
//  DiscoveryBeaconsView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//
//  A reviewable list of beacons heard passively — outside an active discovery scan
//  (FR-015). These are stored session-less (session == nil) and also feed the scan
//  setup's beacon preset / Beacon Channels rows, so a user can include a beaconed
//  mesh in a scan without having run one first.
//

import OSLog
import SwiftData
import SwiftUI

struct DiscoveryBeaconsView: View {
	@Environment(\.modelContext) private var context

	/// All beacons, newest first; passive (session-less) ones are filtered in memory to avoid a
	/// relationship-based SwiftData predicate.
	@Query(sort: \DiscoveredBeaconEntity.timestamp, order: .reverse)
	private var allBeacons: [DiscoveredBeaconEntity]

	private var passiveBeacons: [DiscoveredBeaconEntity] {
		allBeacons.filter { $0.session == nil }
	}

	var body: some View {
		List {
			if passiveBeacons.isEmpty {
				ContentUnavailableView(
					"No Nearby Meshes",
					systemImage: "dot.radiowaves.left.and.right",
					description: Text("Meshes heard advertising themselves via beacons will appear here.")
				)
			} else {
				Section {
					ForEach(passiveBeacons) { beacon in
						beaconRow(beacon)
					}
					.onDelete(perform: deleteBeacons)
				} footer: {
					Text("Meshes heard advertising themselves via beacons, outside a scan. These also pre-select in the next scan setup.")
				}
			}
		}
		.navigationTitle("Nearby Meshes")
	}

	@ViewBuilder
	private func beaconRow(_ beacon: DiscoveredBeaconEntity) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(beacon.displayName)
					.font(.headline)
				Spacer()
				Text("\(String(format: "%.1f", beacon.snr)) SNR")
					.font(.caption)
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}

			if !beacon.message.isEmpty {
				Text(beacon.message)
					.font(.subheadline)
					.fixedSize(horizontal: false, vertical: true)
			}

			let chips = beaconChips(beacon)
			if !chips.isEmpty {
				HStack(spacing: 6) {
					ForEach(chips, id: \.self) { chip in
						Text(chip)
							.font(.caption2)
							.padding(.horizontal, 8)
							.padding(.vertical, 3)
							.background(Color.accentColor.opacity(0.15), in: Capsule())
					}
				}
			}

			Text(beacon.timestamp.formatted(date: .abbreviated, time: .shortened))
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.padding(.vertical, 4)
	}

	private func beaconChips(_ beacon: DiscoveredBeaconEntity) -> [String] {
		var chips: [String] = []
		if let preset = beacon.offeredPreset {
			chips.append(preset.description)
		}
		if let region = beacon.offeredRegion {
			chips.append(region.description)
		}
		if beacon.hasOfferChannel, !beacon.offerChannelName.isEmpty {
			chips.append("#\(beacon.offerChannelName)")
		}
		return chips
	}

	private func deleteBeacons(at offsets: IndexSet) {
		for index in offsets {
			context.delete(passiveBeacons[index])
		}
		do {
			try context.save()
		} catch {
			Logger.data.error("🚫 Failed to delete passive beacon: \(error.localizedDescription, privacy: .public)")
		}
	}
}
