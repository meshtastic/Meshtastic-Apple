//
//  EnvironmentPageIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  The Environment widget's page button. Widgets can't scroll or take swipes,
//  so a large widget set to more than four readings shows four at a time and
//  this flips to the rest. It runs in the widget extension without
//  opening the app and sends nothing over the mesh.
//

import AppIntents
import Foundation
import WidgetKit

enum EnvironmentWidgetPage {
	static let kind = "MeshEnvironment"
	/// Readings on one page of the large size.
	static let pageSize = 4

	/// WidgetKit doesn't say which copy of a widget is which, so the page is
	/// kept per node: two large widgets on the same node flip together.
	private static func key(_ nodeNum: Int64) -> String { "environmentWidgetPage.\(nodeNum)" }

	private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.appGroupID) }

	/// The page to show, wrapped to the pages there are now.
	static func page(for nodeNum: Int64, pageCount: Int) -> Int {
		guard pageCount > 1 else { return 0 }
		return (defaults?.integer(forKey: key(nodeNum)) ?? 0) % pageCount
	}

	static func advance(for nodeNum: Int64, pageCount: Int) {
		defaults?.set(next(after: page(for: nodeNum, pageCount: pageCount), pageCount: pageCount), forKey: key(nodeNum))
	}

	static func next(after page: Int, pageCount: Int) -> Int {
		pageCount > 1 ? (page + 1) % pageCount : 0
	}

	static func pageCount(for metricCount: Int) -> Int {
		max(1, (metricCount + pageSize - 1) / pageSize)
	}

	/// The metrics on `page`.
	static func metrics(_ metrics: [EnvironmentMetric], page: Int) -> [EnvironmentMetric] {
		Array(metrics.dropFirst(page * pageSize).prefix(pageSize))
	}
}

struct EnvironmentPageIntent: AppIntent {
	static let title: LocalizedStringResource = "Next Environment Readings"
	static let description = IntentDescription("Shows the next readings on an Environment widget.")
	/// Only for the widget's button.
	static let isDiscoverable = false

	@Parameter(title: "Node")
	var nodeNum: Int

	@Parameter(title: "Pages")
	var pageCount: Int

	init() {}

	init(nodeNum: Int64, pageCount: Int) {
		self.nodeNum = Int(nodeNum)
		self.pageCount = pageCount
	}

	func perform() async throws -> some IntentResult {
		EnvironmentWidgetPage.advance(for: Int64(nodeNum), pageCount: pageCount)
		WidgetCenter.shared.reloadTimelines(ofKind: EnvironmentWidgetPage.kind)
		return .result()
	}
}
