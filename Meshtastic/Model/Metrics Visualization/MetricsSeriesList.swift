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
	
	var foregroundStyles: Dictionary<String,Color> {
		var dict = Dictionary<String,Color>()
		for aSeries in series {
			dict[aSeries.name] = .clear
		}
		return dict
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
