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

	// CoreData Attribute Name on TelemetryEntity
	let attribute: String

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

	// Main initializer
	init<Value, ChartBody: ChartContent, ForegroundStyle: ShapeStyle>(
		keyPath: KeyPath<TelemetryEntity, Value>,
		name: String,
		abbreviatedName: String,
		conversion: ((Value) -> Value)? = nil,
		visible: Bool = true,
		foregroundStyle: @escaping ((ClosedRange<Float>?) -> ForegroundStyle?) = { _ in nil },
		@ChartContentBuilder chartBody: @escaping (MetricsChartSeries, ClosedRange<Float>?, Date, Value) -> ChartBody?
	) where Value: Plottable & Comparable {

		// This works because TelemetryEntity is an NSManagedObject and derrived from NSObject
		self.attribute = NSExpression(forKeyPath: keyPath).keyPath
		self.name = name
		self.abbreviatedName = abbreviatedName
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
				return conversion(te[keyPath: keyPath]).floatValue
			}
			return te[keyPath: keyPath].floatValue
		}
	}

//	// Return the maximum value for this series attribute given the data
//	func max(forData: [TelemetryEntity]) -> Float? {
//		return forData.compactMap { self.valueClosure($0) }.max()
//	}
//
//	// Return the minimum value for this series attribute given the data
//	func min(forData: [TelemetryEntity]) -> Float? {
//		return forData.compactMap { self.valueClosure($0) }.min()
//	}
//
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
	var id: String { self.attribute }

	static func == (lhs: MetricsChartSeries, rhs: MetricsChartSeries) -> Bool {
		lhs.attribute == rhs.attribute
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(attribute)
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
