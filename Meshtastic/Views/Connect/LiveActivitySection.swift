//
//  LiveActivitySection.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//

import SwiftUI

/// The Connect screen's Live Activity row: start a mesh status activity, or
/// see what's running and stop it. Tracking a node starts from the node's
/// detail screen.
struct LiveActivitySection: View {
	@ObservedObject var liveActivities: MeshLiveActivityManager

	var body: some View {
		Section {
			if let mode = liveActivities.currentMode {
				HStack {
					Label {
						VStack(alignment: .leading, spacing: 2) {
							Text("Live Activity")
							Text(title(for: mode))
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					} icon: {
						Image(systemName: "platter.filled.bottom.iphone")
					}
					Spacer()
					Button("Stop", role: .destructive) {
						liveActivities.stop()
					}
					.buttonStyle(.borderless)
				}
			} else {
				Button {
					liveActivities.start(mode: .meshStatus)
				} label: {
					Label("Start Live Activity", systemImage: "platter.filled.bottom.iphone")
				}
			}
		} footer: {
			if let updatesEndAt = liveActivities.updatesEndAt {
				Text("Updates until \(updatesEndAt.formatted(date: .omitted, time: .shortened)). iOS stops a Live Activity after 8 hours.")
			} else {
				Text("Shows the connection, nodes online, unread messages and battery on the Lock Screen and in the Dynamic Island. To follow one node instead, choose Track in Live Activity on its detail screen.")
			}
		}
	}

	private func title(for mode: LiveActivityMode) -> String {
		switch mode {
		case .meshStatus:
			return String(localized: "Mesh Status")
		case .trackNode:
			if let shortName = liveActivities.trackedNodeShortName {
				return String(localized: "Tracking \(shortName)")
			}
			return String(localized: "Tracking a node")
		}
	}
}
