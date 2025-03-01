//
//  SeriesConfigurationEntry.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/7/24.
//

import Charts
import OSLog
import SwiftUI

// MetricsTableColumn stores metadata about an attribute in TelemetryEntity.
// Given a keypath, this class holds information about how to render the attrbute in
// the table.  MetricsTableColumn objects are collected in a MetricsColumnList
class MetricsTableColumn: ObservableObject {
	// Uniquely identify this column for presistance and iteration
	// Recommend using CoreData Attribute Name on TelemetryEntity
	let id: String

	// Heading for wider tables
	let name: String

	// Heading for space-constrained tables
	let abbreviatedName: String

	// Minimum/maximum grid width for this column
	let minWidth: CGFloat?
	let maxWidth: CGFloat?

	// Recommended spacing, may be overridden
	let spacing: CGFloat
	// Should this column appear in the table

	var visible: Bool

	// Closure to render the table cell
	let tableBodyClosure: (MetricsTableColumn, TelemetryEntity) -> AnyView?

	// Main initializer
	init<Value, TableContent: View>(
		id: String,
		keyPath: KeyPath<TelemetryEntity, Value>,
		name: String,
		abbreviatedName: String,
		minWidth: CGFloat? = nil,
		maxWidth: CGFloat? = nil,
		spacing: CGFloat = 0.1,
		visible: Bool = true,
		@ViewBuilder tableBody: @escaping (MetricsTableColumn, Value) -> TableContent?
	) {
		// This works because TelemetryEntity is an NSManagedObject and derrived from NSObject
		self.id = id
		self.name = name
		self.abbreviatedName = abbreviatedName
		self.minWidth = minWidth
		self.maxWidth = maxWidth
		self.spacing = spacing
		self.visible = visible
		self.tableBodyClosure = { config, entity in
			AnyView(tableBody(config, entity[keyPath: keyPath]))
		}
	}

	var gridItemSize: GridItem.Size {
		if let minWidth, let maxWidth {
			return .flexible(minimum: minWidth, maximum: maxWidth)
		}
		return .flexible()
	}

	func body(_ te: TelemetryEntity) -> AnyView? {
		return tableBodyClosure(self, te)
	}
}

extension MetricsTableColumn: Identifiable, Hashable {
	static func == (lhs: MetricsTableColumn, rhs: MetricsTableColumn) -> Bool {
		lhs.id == rhs.id
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}
