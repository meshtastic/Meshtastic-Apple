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

	/// Namespace under which each series' `visible` flag is persisted. When `nil`, visibility is
	/// not saved (the default for the collection-conformance initializers).
	private let persistenceKey: String?
	/// Backing store for persisted visibility. Defaults to `.standard`; tests inject an isolated suite.
	private let store: UserDefaults

	init(persistenceKey: String? = nil, series: [MetricsChartSeries], store: UserDefaults = .standard) {
		self.series = series
		self.persistenceKey = persistenceKey
		self.store = store
		applyPersistedVisibility()
	}

	var visible: [MetricsChartSeries] {
		return series.filter { $0.visible }
	}

	func toggleVisibity(for aSeries: MetricsChartSeries) {
		if series.contains(aSeries) {
			self.objectWillChange.send()
			aSeries.visible.toggle()
			persistVisibility()
		}
	}

	private var storageKey: String? {
		persistenceKey.map { "metricsSeriesVisibility.\($0)" }
	}

	private func applyPersistedVisibility() {
		MetricsVisibilityPersistence.restore(series, key: storageKey, store: store,
			id: { $0.id }, setVisible: { $0.visible = $1 })
	}

	private func persistVisibility() {
		MetricsVisibilityPersistence.persist(series, key: storageKey, store: store,
			id: { $0.id }, isVisible: { $0.visible })
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

	/// The visible series that have a reading in `data`, grouped by axis in the order they're
	/// listed, each group with the Y range for its readings. A series with no readings gets no
	/// chart and no legend entry (design#53 requirement 11).
	func chartGroups<S: Sequence>(forData data: S) -> [MetricsChartGroup] where S.Element == TelemetryEntity {
		let points = Array(data)
		var groups: [MetricsChartGroup] = []
		for aSeries in visible {
			let values = points.compactMap { aSeries.valueFor($0) }
			guard !values.isEmpty else { continue }
			if let index = groups.firstIndex(where: { $0.axis == aSeries.axis }) {
				groups[index].series.append(aSeries)
				groups[index].values.append(contentsOf: values)
			} else {
				groups.append(MetricsChartGroup(axis: aSeries.axis, series: [aSeries], values: values))
			}
		}
		return groups
	}

	// Collection conformance
	typealias Index = Int
	typealias Element = MetricsChartSeries
	typealias SubSequence = ArraySlice<Element>

	required init() {
		series = []
		persistenceKey = nil
		store = .standard
	}
	required init<S: Sequence>(_ series: S) where S.Element == Element {
		self.series = Array(series)
		persistenceKey = nil
		store = .standard
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

/// The series drawn on one chart, against one axis.
struct MetricsChartGroup: Identifiable {
	let axis: MetricsAxis
	var series: [MetricsChartSeries]
	fileprivate(set) var values: [Float]

	var id: String { axis.id }

	var range: ClosedRange<Float> { axis.range(for: values) }

	func foregroundStyle(forAbbreviatedName name: String) -> AnyShapeStyle? {
		guard let selected = series.first(where: { $0.abbreviatedName == name }) else { return nil }
		return selected.foregroundStyle(range)
	}
}
