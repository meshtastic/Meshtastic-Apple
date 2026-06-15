//
//  SeriesConfiguration.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/7/24.
//
import SwiftUI

class MetricsColumnList: ObservableObject, RandomAccessCollection, RangeReplaceableCollection {

	@Published var columns: [MetricsTableColumn]

	/// Namespace under which each column's `visible` flag is persisted. When `nil`, visibility is
	/// not saved (the default for the collection-conformance initializers).
	private let persistenceKey: String?
	/// Backing store for persisted visibility. Defaults to `.standard`; tests inject an isolated suite.
	private let store: UserDefaults

	init(persistenceKey: String? = nil, columns: [MetricsTableColumn], store: UserDefaults = .standard) {
		self.columns = columns
		self.persistenceKey = persistenceKey
		self.store = store
		applyPersistedVisibility()
	}

	var visible: [MetricsTableColumn] {
		return columns.filter { $0.visible }
	}

	func toggleVisibity(for column: MetricsTableColumn) {
		if columns.contains(column) {
			self.objectWillChange.send()
			column.visible.toggle()
			persistVisibility()
		}
	}

	private var storageKey: String? {
		persistenceKey.map { "metricsColumnVisibility.\($0)" }
	}

	private func applyPersistedVisibility() {
		MetricsVisibilityPersistence.restore(columns, key: storageKey, store: store,
			id: { $0.id }, setVisible: { $0.visible = $1 })
	}

	private func persistVisibility() {
		MetricsVisibilityPersistence.persist(columns, key: storageKey, store: store,
			id: { $0.id }, isVisible: { $0.visible })
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

	required init() {
		columns = []
		persistenceKey = nil
		store = .standard
	}
	required init<S: Sequence>(_ columns: S) where S.Element == Element {
		self.columns = Array(columns)
		persistenceKey = nil
		store = .standard
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

/// Persists a per-element `visible` flag under a namespaced `UserDefaults` key. Shared by
/// `MetricsColumnList` and `MetricsSeriesList`, whose elements both expose a `String` id and a
/// mutable `visible` flag, so the read/cast/loop logic lives here once instead of in each class.
enum MetricsVisibilityPersistence {

	/// Restores each element's `visible` flag from the store. Elements absent from the saved map
	/// (e.g. added in a later app version) keep their current (default) visibility.
	static func restore<Element>(
		_ elements: [Element],
		key: String?,
		store: UserDefaults,
		id: (Element) -> String,
		setVisible: (Element, Bool) -> Void
	) {
		guard let key, let stored = store.dictionary(forKey: key) as? [String: Bool] else { return }
		for element in elements {
			if let isVisible = stored[id(element)] {
				setVisible(element, isVisible)
			}
		}
	}

	/// Persists the current visibility of every element so it survives the view being recreated.
	static func persist<Element>(
		_ elements: [Element],
		key: String?,
		store: UserDefaults,
		id: (Element) -> String,
		isVisible: (Element) -> Bool
	) {
		guard let key else { return }
		var map: [String: Bool] = [:]
		for element in elements {
			map[id(element)] = isVisible(element)
		}
		store.set(map, forKey: key)
	}
}
