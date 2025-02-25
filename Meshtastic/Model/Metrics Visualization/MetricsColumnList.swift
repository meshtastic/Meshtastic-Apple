//
//  SeriesConfiguration.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/7/24.
//
import SwiftUI

class MetricsColumnList: ObservableObject, RandomAccessCollection, RangeReplaceableCollection {

	@Published var columns: [MetricsTableColumn]

	init(columns: [MetricsTableColumn]) {
		self.columns = columns
	}

	var visible: [MetricsTableColumn] {
		return columns.filter { $0.visible }
	}

	func toggleVisibity(for column: MetricsTableColumn) {
		if columns.contains(column) {
			self.objectWillChange.send()
			column.visible.toggle()
		}
	}

	var gridItems: [GridItem] {
		var returnValues: [GridItem] = []
		let columnsInChart = self.visible
		for i in 0..<columnsInChart.count {
			let thisColumn = columnsInChart[i]
			let spacing = (i == columns.count - 1) ? 0 : thisColumn.spacing
			if let min = thisColumn.minWidth, let max = thisColumn.maxWidth {
				returnValues.append(
					GridItem(
						.flexible(minimum: min, maximum: max), spacing: spacing)
				)
			} else {
				returnValues.append(GridItem(.flexible(), spacing: spacing))
			}
		}
		return returnValues
	}

	func column(withId id: String) -> MetricsTableColumn? {
		return columns.first(where: { $0.id == id})
	}

	// Collection conformance
	typealias Index = Int
	typealias Element = MetricsTableColumn
	typealias SubSequence = ArraySlice<Element>

	required init() { columns = [] }
	required init<S: Sequence>(_ columns: S) where S.Element == Element {
		self.columns = Array(columns)
	}

	var startIndex: Int { columns.startIndex }
	var endIndex: Int { columns.endIndex }

	subscript(position: Int) -> Element {
		get { columns[position] }
		set {
			objectWillChange.send()
			columns[position] = newValue
		}
	}
	subscript(bounds: Range<Int>) -> ArraySlice<Element> { columns[bounds] }
	func index(after i: Int) -> Int { columns.index(after: i) }

	func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C) where C.Element == Element {
		objectWillChange.send()
		columns.replaceSubrange(subrange, with: newElements)
	}

	func append(_ newElement: Element) {
		columns.append(newElement)
		objectWillChange.send()
	}

	func remove(at index: Int) -> Element {
		objectWillChange.send()
		let removedElement = columns.remove(at: index)
		return removedElement
	}

	func removeAll() {
		objectWillChange.send()
		columns.removeAll()
	}

	func insert(_ newElement: Element, at index: Int) {
		objectWillChange.send()
		columns.insert(newElement, at: index)
	}
}
