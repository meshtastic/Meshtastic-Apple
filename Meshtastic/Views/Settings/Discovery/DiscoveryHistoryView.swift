// MARK: DiscoveryHistoryView
//
//  DiscoveryHistoryView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import SwiftData
import SwiftUI

struct DiscoveryHistoryView: View {
	@Environment(\.modelContext) private var context

	@Query(sort: \DiscoverySessionEntity.timestamp, order: .reverse)
	private var sessions: [DiscoverySessionEntity]

	var body: some View {
		List {
			if sessions.isEmpty {
				ContentUnavailableView(
					"No Discovery Sessions",
					systemImage: "antenna.radiowaves.left.and.right",
					description: Text("Complete a Local Mesh Discovery scan to see results here.")
				)
			} else {
				ForEach(sessions, id: \.timestamp) { session in
					NavigationLink {
						sessionDetailView(session)
					} label: {
						sessionRow(session)
					}
				}
				.onDelete(perform: deleteSessions)
			}
		}
		.navigationTitle("Session History")
	}

	// MARK: - Session Row

	private func sessionRow(_ session: DiscoverySessionEntity) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
					.font(.headline)
				Spacer()
				statusBadge(session.completionStatus)
			}

			Text(session.presetsScanned.replacingOccurrences(of: ",", with: ", "))
				.font(.subheadline)
				.foregroundStyle(.secondary)

			HStack(spacing: 16) {
				Label("\(session.totalUniqueNodes)", systemImage: "person.2")
				if session.totalTextMessages > 0 {
					Label("\(session.totalTextMessages)", systemImage: "bubble.left")
				}
				if session.totalSensorPackets > 0 {
					Label("\(session.totalSensorPackets)", systemImage: "thermometer.medium")
				}
			}
			.font(.caption)
			.foregroundStyle(.secondary)
		}
		.padding(.vertical, 2)
	}

	// MARK: - Session Detail

	private func sessionDetailView(_ session: DiscoverySessionEntity) -> some View {
		List {
			Section(header: Text("Map")) {
				DiscoveryMapView(
					discoveredNodes: session.discoveredNodes,
					userLatitude: session.userLatitude,
					userLongitude: session.userLongitude,
					isScanning: false
				)
				#if targetEnvironment(macCatalyst)
				.frame(height: 600)
				#else
				.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 450 : 300)
				#endif
				.listRowInsets(EdgeInsets())
			}

			Section {
				NavigationLink {
					DiscoverySummaryView(session: session)
				} label: {
					Label("View Full Summary", systemImage: "chart.bar.doc.horizontal")
				}
			}
		}
		.navigationTitle("Session Detail")
	}

	// MARK: - Delete

	private func deleteSessions(at offsets: IndexSet) {
		for index in offsets {
			context.delete(sessions[index])
		}
		try? context.save()
	}

	// MARK: - Helpers

	@ViewBuilder
	private func statusBadge(_ status: String) -> some View {
		let (color, icon): (Color, String) = switch status {
		case "complete": (.green, "checkmark.circle.fill")
		case "stopped": (.orange, "stop.circle.fill")
		case "interrupted": (.red, "exclamationmark.circle.fill")
		default: (.gray, "circle.dashed")
		}

		Label(status.capitalized, systemImage: icon)
			.foregroundStyle(color)
			.font(.caption)
	}
}
