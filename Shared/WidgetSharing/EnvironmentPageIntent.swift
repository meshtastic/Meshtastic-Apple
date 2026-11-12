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
	/// Readings on one page of the extra large portrait size, with more than this picked.
	static let extraLargePortraitPageSize = 6

	/// WidgetKit doesn't say which copy of a widget is which, so the page is
	/// kept per node: two large widgets on the same node flip together.
	private static func key(_ nodeNum: Int64) -> String { "environmentWidgetPage.\(nodeNum)" }

	private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.appGroupID) }

	/// The page as stored, before wrapping to the pages a size has.
	static func storedPage(for nodeNum: Int64) -> Int {
		defaults?.integer(forKey: key(nodeNum)) ?? 0
	}

	/// The page to show, wrapped to the pages there are now.
	static func page(for nodeNum: Int64, pageCount: Int) -> Int {
		wrap(storedPage(for: nodeNum), pageCount: pageCount)
	}

	static func wrap(_ page: Int, pageCount: Int) -> Int {
		pageCount > 1 ? page % pageCount : 0
	}

	static func advance(for nodeNum: Int64, pageCount: Int) {
		defaults?.set(next(after: page(for: nodeNum, pageCount: pageCount), pageCount: pageCount), forKey: key(nodeNum))
	}

	static func next(after page: Int, pageCount: Int) -> Int {
		pageCount > 1 ? (page + 1) % pageCount : 0
	}

	static func pageCount(for metricCount: Int, pageSize: Int = pageSize) -> Int {
		max(1, (metricCount + pageSize - 1) / pageSize)
	}

	/// The columns and rows that give `count` square tiles the largest side in `size`,
	/// with at least `spacing` between rows and across each row, edges included.
	static func bestFit(count: Int, in size: CGSize, spacing: CGFloat) -> (columns: Int, rows: Int, side: CGFloat) {
		var best = (columns: 1, rows: max(1, count), side: CGFloat(0))
		for columns in 1...max(1, count) {
			let rows = (count + columns - 1) / columns
			let side = min(
				(size.width - spacing * CGFloat(columns + 1)) / CGFloat(columns),
				(size.height - spacing * CGFloat(max(0, rows - 1))) / CGFloat(max(1, rows))
			)
			if side > best.side {
				best = (columns, max(1, rows), side)
			}
		}
		return (best.columns, best.rows, max(0, best.side))
	}

	/// The metrics on `page`.
	static func metrics(_ metrics: [EnvironmentMetric], page: Int, pageSize: Int = pageSize) -> [EnvironmentMetric] {
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
