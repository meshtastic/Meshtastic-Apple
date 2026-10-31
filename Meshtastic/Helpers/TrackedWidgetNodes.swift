//
//  TrackedWidgetNodes.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
//  The nodes the person's Node Tracker widgets are set to, as iOS reports
//  them. The widget snapshot always carries these nodes, and deleting one
//  says it's on a widget.
//

import Foundation
import OSLog
import WidgetKit

@MainActor
final class TrackedWidgetNodes {
	static let shared = TrackedWidgetNodes()

	/// Empty until iOS has answered.
	private(set) var nums: Set<Int64> = []
	private var readAt: Date?

	private init() {}

	/// Added to the delete confirmation for a node on a tracker.
	static var deleteWarning: String {
		String(localized: "This node is on a Node Tracker widget. The widget will say it's no longer in your node list until you choose another node or the node is heard again.", comment: "Delete node confirmation: the node is shown on a Node Tracker widget")
	}

	/// Reads the trackers' configurations again, at most once a minute; iOS has
	/// no change notification for them.
	func refresh() async {
		if let readAt, Date().timeIntervalSince(readAt) < 60 { return }
		readAt = .now
		// The callback form: the async one is iOS 18 and later.
		let result = await withCheckedContinuation { continuation in
			WidgetCenter.shared.getCurrentConfigurations { continuation.resume(returning: $0) }
		}
		switch result {
		case .success(let infos):
			nums = Set(infos.compactMap { info in
				guard info.kind == "MeshNodeTracker" else { return nil }
				return info.widgetConfigurationIntent(of: TrackNodeIntent.self)?.node?.nodeNum
			})
		case .failure(let error):
			Logger.services.debug("🧩 Widget configurations unavailable: \(error.localizedDescription, privacy: .public)")
		}
	}
}
