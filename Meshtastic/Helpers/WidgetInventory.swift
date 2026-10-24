//
//  WidgetInventory.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
//  Which Meshtastic widgets and controls are on the person's screens, as iOS
//  reports them. An app can't add or configure a widget itself — that only
//  happens on the Home Screen, Lock Screen or in Control Center — so the
//  Widgets sheet shows what's there and how to add the rest.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import OSLog
import SwiftUI
import WidgetKit

@MainActor
final class WidgetInventory: ObservableObject {
	static let shared = WidgetInventory()

	/// A widget the extension offers.
	struct WidgetKind: Identifiable {
		let kind: String
		let title: LocalizedStringKey
		let systemImage: String
		var id: String { kind }
	}

	/// A control the extension offers.
	struct ControlKind: Identifiable {
		let kind: String
		let title: LocalizedStringKey
		let systemImage: String
		var id: String { kind }
	}

	/// Kept in step with the kinds in the widget extension.
	static let widgets: [WidgetKind] = [
		WidgetKind(kind: "MeshLocalStats", title: "Mesh Status", systemImage: "antenna.radiowaves.left.and.right"),
		WidgetKind(kind: "MeshNodeTracker", title: "Node Tracker", systemImage: "scope"),
		WidgetKind(kind: "MeshMessages", title: "Messages", systemImage: "message"),
		WidgetKind(kind: "MeshNodeMap", title: "Node Map", systemImage: "map"),
		WidgetKind(kind: "MeshTraceRoute", title: "Trace Route", systemImage: "point.3.connected.trianglepath.dotted")
	]

	static let controls: [ControlKind] = [
		ControlKind(kind: "MeshOpenMessages", title: "Mesh Messages", systemImage: "message.fill"),
		ControlKind(kind: "MeshOpenConnect", title: "Connect Radio", systemImage: "antenna.radiowaves.left.and.right"),
		ControlKind(kind: "MeshOpenMap", title: "Mesh Map", systemImage: "map.fill")
	]

	/// The sizes of each kind that are on a screen.
	@Published private(set) var families: [String: Set<WidgetFamily>] = [:]
	/// The control kinds that are added somewhere; nil before iOS 18 or until read.
	@Published private(set) var controlKinds: Set<String>?

	private init() {}

	/// How many Meshtastic widgets are on a screen.
	var addedWidgetCount: Int {
		families.values.reduce(0) { $0 + $1.count }
	}

	/// Reads the current configurations again; cheap, and iOS has no change
	/// notification, so call it when the sheet or the app comes forward.
	func refresh() {
		WidgetCenter.shared.getCurrentConfigurations { result in
			Task { @MainActor in
				switch result {
				case .success(let infos):
					var byKind: [String: Set<WidgetFamily>] = [:]
					for info in infos {
						byKind[info.kind, default: []].insert(info.family)
					}
					self.families = byKind
				case .failure(let error):
					Logger.services.debug("🧩 Widget configurations unavailable: \(error.localizedDescription, privacy: .public)")
				}
			}
		}
		if #available(iOS 18.0, *) {
			Task {
				do {
					let controls = try await ControlCenter.shared.currentControls()
					controlKinds = Set(controls.map(\.kind))
				} catch {
					Logger.services.debug("🧩 Controls unavailable: \(error.localizedDescription, privacy: .public)")
				}
			}
		}
	}

	/// "Small, Medium · Lock Screen", or nil when the kind isn't on any screen.
	func addedDescription(for kind: String) -> String? {
		guard let added = families[kind], !added.isEmpty else { return nil }
		let homeOrder: [(WidgetFamily, String)] = [
			(.systemSmall, String(localized: "Small")),
			(.systemMedium, String(localized: "Medium")),
			(.systemLarge, String(localized: "Large")),
			(.systemExtraLarge, String(localized: "Extra Large"))
		]
		var parts = homeOrder.filter { added.contains($0.0) }.map(\.1)
		let lockScreen: Set<WidgetFamily> = [.accessoryInline, .accessoryCircular, .accessoryRectangular]
		if !added.isDisjoint(with: lockScreen) {
			parts.append(String(localized: "Lock Screen"))
		}
		return parts.joined(separator: ", ")
	}
}
#endif
