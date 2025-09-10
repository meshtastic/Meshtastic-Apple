//
//  MetricsChartSeriesList.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/24.
//

import Foundation
import SwiftUI

class MetricsSeriesList: ObservableObject, RandomAccessCollection, RangeReplaceableCollection {

	@Published var series: [MetricsChartSeries]

	var visible: [MetricsChartSeries] {
		return series.filter { $0.visible }
	}

	func toggleVisibity(for aSeries: MetricsChartSeries) {
		if series.contains(aSeries) {
			self.objectWillChange.send()
			aSeries.visible.toggle()
		}
	}

	func foregroundStyle<T>(forName: String, chartRange: ClosedRange<T>? = nil) -> AnyShapeStyle? where T: BinaryFloatingPoint {
		if let selectedSeries = series.first(where: { $0.name == forName }) {
			let range = chartRange.map { Float($0.lowerBound)...Float($0.upperBound) }
			return selectedSeries.foregroundStyle(range)
		}
		return nil
	}

	func foregroundStyle<T>(forAbbreviatedName: String, chartRange: ClosedRange<T>? = nil) -> AnyShapeStyle? where T: BinaryFloatingPoint {
		if let selectedSeries = series.first(where: { $0.abbreviatedName == forAbbreviatedName }) {
			let range = chartRange.map { Float($0.lowerBound)...Float($0.upperBound) }
			return selectedSeries.foregroundStyle(range)
		}
		return nil
	}

	// Calculates the chartRange based on the series configuration and data provided
	// Besides checkign the range of the data, this function also obeys some series-level
	// configuraiton, such as:
	//   1. starting with a desired fixed range
	//   2. obeying a minimum span
	func chartRange<S: Sequence>(forData data: S) -> ClosedRange<Float> where S.Element == TelemetryEntity {
		var globalLower: Float = .infinity
		var globalUpper: Float = -.infinity

		// Keep track of the range of each series
		var range: [MetricsChartSeries: ClosedRange<Float>] = [:]

		// Determine if there is an initial fixed range.
		// The range might exapand past this initial range if the data goes beyond.
		for aSeries in self.visible {
			if let thisRange = aSeries.initialYAxisRange {
				range[aSeries] = thisRange
				if thisRange.upperBound > globalUpper {globalUpper = thisRange.upperBound}
				if thisRange.lowerBound < globalLower {globalLower = thisRange.lowerBound}
			}
		}

		// Iterate through all the data. It would be easier to iterate
		// the series then the data, but this way we only iterate the data once
		for te in data {
			for aSeries in self.visible {
				var seriesUpper = range[aSeries]?.upperBound ?? -.infinity
				var seriesLower = range[aSeries]?.lowerBound ?? .infinity

				if let value = aSeries.valueFor(te) {
					// Update the global bounds
					if value > globalUpper {globalUpper = value}
					if value < globalLower {globalLower = value}

					// Update the series bounds if necessary
					if value > seriesUpper || value < seriesLower {
						if value > seriesUpper {
							seriesUpper = value
						}
						if value < seriesLower {
							seriesLower = value
						}
						if seriesUpper.isFinite && seriesLower.isFinite {
							range[aSeries] = seriesLower...seriesUpper
						}
					}
				}
			}
		}

		// Go through each series one last time to obey the minimum span
		for aSeries in self.visible {
			if let minimumSpan = aSeries.minumumYAxisSpan,
			   let currentRange = range[aSeries] {
				let currentSpan = currentRange.upperBound - currentRange.lowerBound
				if currentSpan < minimumSpan {
					// Calculate the center of the range
					let centerOfRange = currentRange.lowerBound + (currentSpan / 2)
					let newLower = centerOfRange - (minimumSpan / 2.0)
					let newUpper = centerOfRange + (minimumSpan / 2.0)

					if newUpper > globalUpper {
						globalUpper = newUpper
					}
					if newLower < globalLower {
						globalLower = newLower
					}
				}
			}
		}

		// Return default range if no data
		if !globalLower.isFinite || !globalUpper.isFinite {
			return 0.0...100.0
		}
		return globalLower...globalUpper
	}

	// Collection conformance
	typealias Index = Int
	typealias Element = MetricsChartSeries
	typealias SubSequence = ArraySlice<Element>

	required init() { series = [] }
	required init<S: Sequence>(_ series: S) where S.Element == Element {
		self.series = Array(series)
	}

	var startIndex: Int { series.startIndex }
	var endIndex: Int { series.endIndex }

	subscript(position: Int) -> Element {
		get { series[position] }
		set {
			objectWillChange.send()
			series[position] = newValue
		}
	}
	subscript(bounds: Range<Int>) -> ArraySlice<Element> { series[bounds] }
	func index(after i: Int) -> Int { series.index(after: i) }

	func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C) where C.Element == Element {
		objectWillChange.send()
		series.replaceSubrange(subrange, with: newElements)
	}

	func append(_ newElement: Element) {
		series.append(newElement)
		objectWillChange.send()
	}

	func remove(at index: Int) -> Element {
		objectWillChange.send()
		let removedElement = series.remove(at: index)
		return removedElement
	}

	func removeAll() {
		objectWillChange.send()
		series.removeAll()
	}

	func insert(_ newElement: Element, at index: Int) {
		objectWillChange.send()
		series.insert(newElement, at: index)
	}

}
