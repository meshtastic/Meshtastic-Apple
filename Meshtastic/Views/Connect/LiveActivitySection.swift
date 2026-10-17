//
//  LiveActivitySection.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//

import SwiftUI

/// The Connect screen's Live Activity row: what's running, and a tap to
/// choose what it shows, switch it or stop it.
struct LiveActivitySection: View {
	@ObservedObject var liveActivities: MeshLiveActivityManager
	/// Opens the chooser, which Connect presents from its list.
	let openChooser: () -> Void

	var body: some View {
		Section {
			Button {
				openChooser()
			} label: {
				HStack {
					Label("Live Activity", systemImage: "platter.filled.bottom.iphone")
						.foregroundStyle(.primary)
					Spacer(minLength: 8)
					Text(status)
						.foregroundStyle(.secondary)
					Image(systemName: "chevron.right")
						.font(.footnote.weight(.semibold))
						.foregroundStyle(.tertiary)
				}
			}
		} footer: {
			if let updatesEndAt = liveActivities.updatesEndAt {
				Text("Updates until \(updatesEndAt.formatted(date: .omitted, time: .shortened)).")
			} else {
				Text("Show the mesh or one node on the Lock Screen and in the Dynamic Island.")
			}
		}
	}

	private var status: String {
		switch liveActivities.currentMode {
		case nil:
			return String(localized: "Off")
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
