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

	func chartRange(forData data: [TelemetryEntity]) -> ClosedRange<Float> {
		var lower: Float?
		var upper: Float?
		for te in data {
			for aSeries in self.visible {
				if let value = aSeries.valueFor(te) {
					if value > (upper ?? -.infinity) {upper = value}
					if value < (lower ?? .infinity) {lower = value}
				}
			}
		}
		
		// Return default range if no data or nil
		guard let lower, let upper else {
			return 0.0...100.0
		}
		return lower...upper
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
