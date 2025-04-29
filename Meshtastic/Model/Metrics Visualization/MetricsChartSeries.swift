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

	// Uniquely identify this column for presistance and iteration
	// Recommend using CoreData Attribute Name on TelemetryEntity
	let id: String

	// Heading for areas that have the room
	let name: String

	// Heading for space-constrained areas
	let abbreviatedName: String

	// Should this column appear in the chart
	var visible: Bool

	// A closure that will provide the foreground style given the data set and overall chart range
	let foregroundStyle: (ClosedRange<Float>?) -> AnyShapeStyle?

	// A closure that will provide the Chart Content for this series
	let chartBodyClosure:
		(MetricsChartSeries, ClosedRange<Float>?, TelemetryEntity) -> AnyChartContent?  // Closure to render the chart

	// A closure that will privide the value of a TelemetryEntity for this series
	// Possibly converted to the proper units
	let valueClosure: (TelemetryEntity) -> Float?

	// Used for scaling the Y-axis
	let initialYAxisRange: ClosedRange<Float>?
	let minumumYAxisSpan: Float?
	// Main initializer
	init<Value, ChartBody: ChartContent, ForegroundStyle: ShapeStyle>(
		id: String,
		keyPath: KeyPath<TelemetryEntity, Value>,
		name: String,
		abbreviatedName: String,
		initialYAxisRange: ClosedRange<Float>? = nil,
		minumumYAxisSpan: Float? = nil,
		conversion: ((Value) -> Value)? = nil,
		visible: Bool = true,
		foregroundStyle: @escaping ((ClosedRange<Float>?) -> ForegroundStyle?) = { _ in nil },
		@ChartContentBuilder chartBody: @escaping (MetricsChartSeries, ClosedRange<Float>?, Date, Value) -> ChartBody?
	) {

		// This works because TelemetryEntity is an NSManagedObject and derrived from NSObject
		self.id = id
		self.name = name
		self.abbreviatedName = abbreviatedName
		self.initialYAxisRange = initialYAxisRange
		self.minumumYAxisSpan = minumumYAxisSpan
		self.visible = visible

		// By saving these closures, MetricsChartSeries can be type agnostic
		// This is a less elegant form of type erasure, but doesn't require a new Any-type
		self.foregroundStyle = { range in foregroundStyle(range).map({ AnyShapeStyle($0) }) }
		self.chartBodyClosure = { series, range, entity in
			AnyChartContent(
				chartBody(series, range, entity.time!, entity[keyPath: keyPath]))
		}
		self.valueClosure = { te in
			if let conversion {
				if let value = conversion(te[keyPath: keyPath]) as? (any Plottable) {
					return value.floatValue ?? 0.0
				}
			} else {
				if let value = te[keyPath: keyPath] as? (any Plottable) {
					return value.floatValue
				}
			}
			return nil
		}
	}

	// Return the value for this series attribute given a full row of telemetry data
	func valueFor(_ te: TelemetryEntity) -> Float? {
		return self.valueClosure(te)?.floatValue
	}

	// Return the chart content for this series given a full row of telemetry data
	func body<T>(_ te: TelemetryEntity, inChartRange chartRange: ClosedRange<T>? = nil) -> AnyChartContent? where T: BinaryFloatingPoint {
		let range = chartRange.map { Float($0.lowerBound)...Float($0.upperBound) }
		return chartBodyClosure(self, range, te)
	}
}

extension MetricsChartSeries: Identifiable, Hashable {

	static func == (lhs: MetricsChartSeries, rhs: MetricsChartSeries) -> Bool {
		lhs.id == rhs.id
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

extension Plottable {
	var floatValue: Float? {
		if let integerValue = self.primitivePlottable as? any BinaryInteger {
			return Float(integerValue)
		} else if let floatingPointValue = self.primitivePlottable as? any BinaryFloatingPoint {
			return Float(floatingPointValue)
		}
		return nil
	}
	var doubleValue: Double? {
		if let integerValue = self.primitivePlottable as? any BinaryInteger {
			return Double(integerValue)
		} else if let floatingPointValue = self.primitivePlottable as? any BinaryFloatingPoint {
			return Double(floatingPointValue)
		}
		return nil
	}
}
