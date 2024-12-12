//
//  MetricsChartSeries.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/24.
//

import Charts
import Foundation
import SwiftUI

// MetricsChartSeries stores metadata about an attribute in TelemetryEntity.
// Given a keypath, this class holds information about how to render the attrbute in a
// the chart.  MetricsChartSeries objects are collected in a MetricsSeriesList
class MetricsChartSeries: ObservableObject {
	
	let attribute: String  // CoreData Attribute Name on TelemetryEntity
	let name: String  // Heading for wider tables
	let abbreviatedName: String  // Heading for space-constrained tables
	var visible: Bool  // Should this column appear in the table
	let chartBodyClosure:
		(MetricsChartSeries, TelemetryEntity) -> AnyChartContent?  // Closure to render the chart

	// Main initializer
	init<Value, ChartBody: ChartContent>(
		keyPath: KeyPath<TelemetryEntity, Value>,
		name: String,
		abbreviatedName: String,
		visible: Bool = true,
		@ChartContentBuilder chartBody: @escaping (MetricsChartSeries, Date, Value) -> ChartBody?
	) {
		// This works because TelemetryEntity is an NSManagedObject and derrived from NSObject
		self.attribute = NSExpression(forKeyPath: keyPath).keyPath
		self.name = name
		self.abbreviatedName = abbreviatedName
		self.visible = visible
		self.chartBodyClosure = { series, entity in
			AnyChartContent(
				chartBody(series, entity.time!, entity[keyPath: keyPath]))
		}
	}

	func body(_ te: TelemetryEntity) -> AnyChartContent? {
		return chartBodyClosure(self, te)
	}
}

extension MetricsChartSeries: Identifiable, Hashable {
	var id: String { self.attribute }

	static func == (lhs: MetricsChartSeries, rhs: MetricsChartSeries) -> Bool {
		lhs.attribute == rhs.attribute
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(attribute)
	}
}
