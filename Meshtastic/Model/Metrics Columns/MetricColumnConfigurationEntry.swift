//
//  SeriesConfigurationEntry.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/7/24.
//

import SwiftUI
import Charts
import OSLog

struct MetricVisualizationType: OptionSet {
	let rawValue: Int
	
	static let chart = MetricVisualizationType(rawValue: 1 << 0)
	static let table = MetricVisualizationType(rawValue: 1 << 1)
	
	static let all: MetricVisualizationType = [.chart, .table]
}
class MetricsColumnConfigurationEntry: ObservableObject {
	let attribute: String		// CoreData Attribute Name on TelemetryEntity
	let availability: MetricVisualizationType // Determine where this attribute can appear
	let columnName: String 		// Heading for wider tables
	let abbreviatedColumnName: String // Heading for space-constrained tables
	let minWidth: CGFloat?  		// Minimum grid width for this column
	let maxWidth: CGFloat?  		// Maximum grid width for this column
	let spacing: CGFloat	    	// Recommended spacing, may be overridden
	var showInTable: Bool		// Should this column appear in the table
	var showInChart: Bool    	// Should this column appear in the chart
	let tableBodyClosure: (MetricsColumnConfigurationEntry, TelemetryEntity) -> AnyView // Closure to render the view
	let chartBodyClosure: (MetricsColumnConfigurationEntry, TelemetryEntity) -> AnyChartContent // Closure to render the chart
	
	init<Value, TableContent: View, ChartAxes: ChartContent>(attribute: String, keyPath: KeyPath<TelemetryEntity, Value>,
				availability: MetricVisualizationType = .all,
				columnName: String, abbreviatedColumnName: String,
				minWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, spacing: CGFloat = 0.1,
				showInTable: Bool = true, showInChart: Bool = false,
				@ViewBuilder tableBody:  @escaping (MetricsColumnConfigurationEntry, Value) -> TableContent,
				@ChartContentBuilder chartBody:  @escaping (MetricsColumnConfigurationEntry, Date, Value) -> ChartAxes) {
		self.attribute = attribute
		self.availability = availability
		self.columnName = columnName
		self.abbreviatedColumnName = abbreviatedColumnName
		self.minWidth = minWidth
		self.maxWidth = maxWidth
		self.spacing = spacing
		self.showInTable = showInTable
		self.showInChart = showInChart
		self.tableBodyClosure = { config, entity in AnyView(tableBody(config, entity[keyPath: keyPath])) }
		self.chartBodyClosure = { config, entity in AnyChartContent(chartBody(config, entity.time!, entity[keyPath: keyPath])) }
	}

	var gridItemSize: GridItem.Size {
		if let minWidth, let maxWidth {
			return .flexible(minimum: minWidth, maximum: maxWidth)
		}
		return .flexible()
	}

	func tableBody(_ te: TelemetryEntity) -> AnyView {
		return tableBodyClosure(self, te)
	}

	func chartBody(_ te: TelemetryEntity) -> AnyChartContent {
		return chartBodyClosure(self, te)
	}

}

extension MetricsColumnConfigurationEntry: Identifiable, Hashable {
	var id: String { self.attribute }

	static func == (lhs: MetricsColumnConfigurationEntry, rhs: MetricsColumnConfigurationEntry) -> Bool {
		lhs.attribute == rhs.attribute
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(attribute)
	}
}
