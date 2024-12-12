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

	let attribute: String  // CoreData Attribute Name on TelemetryEntity
	let name: String  // Heading for wider tables
	let abbreviatedName: String  // Heading for space-constrained tables
	let minWidth: CGFloat?  // Minimum grid width for this column
	let maxWidth: CGFloat?  // Maximum grid width for this column
	let spacing: CGFloat  // Recommended spacing, may be overridden
	var visible: Bool  // Should this column appear in the table
	let tableBodyClosure: (MetricsTableColumn, TelemetryEntity) -> AnyView?  // Closure to render the view

	// Main initializer
	init<Value, TableContent: View>(
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
		self.attribute = NSExpression(forKeyPath: keyPath).keyPath
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
	var id: String { self.attribute }

	static func == (lhs: MetricsTableColumn, rhs: MetricsTableColumn) -> Bool {
		lhs.attribute == rhs.attribute
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(attribute)
	}
}
