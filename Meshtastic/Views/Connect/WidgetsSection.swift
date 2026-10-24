//
//  WidgetsSection.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftUI

/// The Connect screen's Widgets row: what's running or added, and a tap to
/// open the sheet that covers the Live Activity, widgets and controls.
struct WidgetsSection: View {
	@ObservedObject var liveActivities: MeshLiveActivityManager
	@ObservedObject var inventory: WidgetInventory
	/// Opens the sheet, which Connect presents from its list.
	let openSheet: () -> Void

	var body: some View {
		Section {
			Button {
				openSheet()
			} label: {
				HStack {
					Label("Widgets", systemImage: "square.grid.2x2")
						.foregroundStyle(.primary)
					Spacer(minLength: 8)
					Text(status)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.trailing)
					Image(systemName: "chevron.right")
						.font(.footnote.weight(.semibold))
						.foregroundStyle(.tertiary)
				}
			}
		} footer: {
			Text("Live Activity, Home Screen and Lock Screen widgets, and controls.")
		}
		.onAppear {
			inventory.refresh()
		}
	}

	/// The running Live Activity first, since it's the one that changes most;
	/// otherwise how many widgets are on a screen.
	private var status: String {
		switch liveActivities.currentMode {
		case .meshStatus:
			return String(localized: "Mesh Status")
		case .trackNode:
			if let shortName = liveActivities.trackedNodeShortName {
				return String(localized: "Tracking \(shortName)")
			}
			return String(localized: "Tracking a node")
		case nil:
			// Nothing claimed until iOS says what's there.
			guard let count = inventory.addedWidgetCount else { return "" }
			return count == 0 ? String(localized: "None added") : String(localized: "\(count) added")
		}
	}
}
#endif
