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
final class TrackedWidgetNodes: ObservableObject {
	static let shared = TrackedWidgetNodes()

	/// Nil until iOS has answered once.
	@Published private(set) var nums: Set<Int64>?
	private var readAt: Date?
	private var reading: Task<Void, Never>?

	private init() {}

	func contains(_ num: Int64) -> Bool {
		nums?.contains(num) ?? false
	}

	/// Added to the delete confirmation for a node on a tracker.
	static var deleteWarning: String {
		String(localized: "This node is on a Node Tracker widget. The widget will say it's no longer in your node list until you choose another node or the node is heard again.", comment: "Delete node confirmation: the node is shown on a Node Tracker widget")
	}

	/// Reads the trackers' configurations again, at most once a minute after a
	/// read that worked; iOS has no change notification for them. A call while
	/// a read is running waits for it.
	func refresh() async {
		if let reading {
			await reading.value
			return
		}
		if let readAt, Date().timeIntervalSince(readAt) < 60 { return }
		let read = Task {
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
				readAt = .now
			case .failure(let error):
				Logger.services.debug("🧩 Widget configurations unavailable: \(error.localizedDescription, privacy: .public)")
			}
		}
		reading = read
		await read.value
		reading = nil
	}
}
