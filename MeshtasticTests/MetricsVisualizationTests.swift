import Foundation
import Testing
import SwiftUI
import Charts

@testable import Meshtastic

// MARK: - MetricsColumnList Collection Tests

@Suite("MetricsColumnList Collection")
struct MetricsColumnListCollectionTests {

	private func makeColumn(id: String, visible: Bool = true) -> MetricsTableColumn {
		MetricsTableColumn(
			id: id,
			keyPath: \TelemetryEntity.batteryLevel,
			name: id,
			abbreviatedName: id,
			visible: visible
		) { _, _ in
			EmptyView()
		}
	}

	@Test func init_empty() {
		let list = MetricsColumnList()
		#expect(list.count == 0)
		#expect(list.startIndex == 0)
		#expect(list.endIndex == 0)
	}

	@Test func init_withColumns() {
		let col1 = makeColumn(id: "a")
		let col2 = makeColumn(id: "b")
		let list = MetricsColumnList(columns: [col1, col2])
		#expect(list.count == 2)
	}

	@Test func init_fromSequence() {
		let col = makeColumn(id: "a")
		let list = MetricsColumnList([col])
		#expect(list.count == 1)
	}

	@Test func subscript_get() {
		let col = makeColumn(id: "test")
		let list = MetricsColumnList(columns: [col])
		#expect(list[0].id == "test")
	}

	@Test func subscript_set() {
		let col1 = makeColumn(id: "a")
		let col2 = makeColumn(id: "b")
		let list = MetricsColumnList(columns: [col1])
		list[0] = col2
		#expect(list[0].id == "b")
	}

	@Test func subscript_range() {
		let col1 = makeColumn(id: "a")
		let col2 = makeColumn(id: "b")
		let col3 = makeColumn(id: "c")
		let list = MetricsColumnList(columns: [col1, col2, col3])
		let slice = list[0..<2]
		#expect(slice.count == 2)
	}

	@Test func indexAfter() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a")])
		#expect(list.index(after: 0) == 1)
	}

	@Test func append() {
		let list = MetricsColumnList()
		list.append(makeColumn(id: "new"))
		#expect(list.count == 1)
		#expect(list[0].id == "new")
	}

	@Test func remove_at() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a"), makeColumn(id: "b")])
		let removed = list.remove(at: 0)
		#expect(removed.id == "a")
		#expect(list.count == 1)
		#expect(list[0].id == "b")
	}

	@Test func removeAll() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a"), makeColumn(id: "b")])
		list.removeAll()
		#expect(list.count == 0)
	}

	@Test func insert() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a"), makeColumn(id: "c")])
		list.insert(makeColumn(id: "b"), at: 1)
		#expect(list.count == 3)
		#expect(list[1].id == "b")
	}

	@Test func replaceSubrange() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a"), makeColumn(id: "b"), makeColumn(id: "c")])
		list.replaceSubrange(1..<2, with: [makeColumn(id: "x"), makeColumn(id: "y")])
		#expect(list.count == 4)
		#expect(list[1].id == "x")
		#expect(list[2].id == "y")
	}

	@Test func visible_filtersCorrectly() {
		let list = MetricsColumnList(columns: [
			makeColumn(id: "a", visible: true),
			makeColumn(id: "b", visible: false),
			makeColumn(id: "c", visible: true),
		])
		#expect(list.visible.count == 2)
	}

	@Test func toggleVisibility() {
		let col = makeColumn(id: "a", visible: true)
		let list = MetricsColumnList(columns: [col])
		#expect(col.visible == true)
		list.toggleVisibity(for: col)
		#expect(col.visible == false)
		list.toggleVisibity(for: col)
		#expect(col.visible == true)
	}

	@Test func toggleVisibility_nonExistentColumn_noOp() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a")])
		let outsideCol = makeColumn(id: "b")
		list.toggleVisibity(for: outsideCol)
		// Should not crash or affect anything
		#expect(outsideCol.visible == true)
	}

	@Test func columnWithId_found() {
		let list = MetricsColumnList(columns: [
			makeColumn(id: "a"),
			makeColumn(id: "b"),
		])
		let found = list.column(withId: "b")
		#expect(found?.id == "b")
	}

	@Test func columnWithId_notFound() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a")])
		#expect(list.column(withId: "z") == nil)
	}

	@Test func gridItems_matchesVisibleCount() {
		let list = MetricsColumnList(columns: [
			makeColumn(id: "a", visible: true),
			makeColumn(id: "b", visible: false),
			makeColumn(id: "c", visible: true),
		])
		#expect(list.gridItems.count == 2)
	}
}

// MARK: - MetricsTableColumn

@Suite("MetricsTableColumn Properties")
struct MetricsTableColumnPropertyTests {

	@Test func identifiable() {
		let col = MetricsTableColumn(
			id: "test",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "Test",
			abbreviatedName: "T",
			visible: true
		) { _, _ in EmptyView() }
		#expect(col.id == "test")
	}

	@Test func hashable_sameId() {
		let col1 = MetricsTableColumn(
			id: "test",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "Test A",
			abbreviatedName: "A",
			visible: true
		) { _, _ in EmptyView() }
		let col2 = MetricsTableColumn(
			id: "test",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "Test B",
			abbreviatedName: "B",
			visible: false
		) { _, _ in EmptyView() }
		#expect(col1 == col2)
		#expect(col1.hashValue == col2.hashValue)
	}

	@Test func hashable_differentId() {
		let col1 = MetricsTableColumn(
			id: "a",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "A",
			abbreviatedName: "A",
			visible: true
		) { _, _ in EmptyView() }
		let col2 = MetricsTableColumn(
			id: "b",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "B",
			abbreviatedName: "B",
			visible: true
		) { _, _ in EmptyView() }
		#expect(col1 != col2)
	}

	@Test func gridItemSize_withMinMax() {
		let col = MetricsTableColumn(
			id: "test",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "Test",
			abbreviatedName: "T",
			minWidth: 50,
			maxWidth: 100,
			visible: true
		) { _, _ in EmptyView() }
		// gridItemSize returns .flexible(minimum:maximum:) when both are set
		let size = col.gridItemSize
		// We just verify it doesn't crash and returns a value
		_ = size
	}

	@Test func gridItemSize_withoutMinMax() {
		let col = MetricsTableColumn(
			id: "test",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "Test",
			abbreviatedName: "T",
			visible: true
		) { _, _ in EmptyView() }
		let size = col.gridItemSize
		_ = size
	}

	@Test func defaultSpacing() {
		let col = MetricsTableColumn(
			id: "test",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "Test",
			abbreviatedName: "T",
			visible: true
		) { _, _ in EmptyView() }
		#expect(col.spacing == 0.1)
	}

	@Test func customSpacing() {
		let col = MetricsTableColumn(
			id: "test",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "Test",
			abbreviatedName: "T",
			spacing: 5.0,
			visible: true
		) { _, _ in EmptyView() }
		#expect(col.spacing == 5.0)
	}

	@Test func properties() {
		let col = MetricsTableColumn(
			id: "myId",
			keyPath: \TelemetryEntity.batteryLevel,
			name: "Battery Level",
			abbreviatedName: "Bat",
			minWidth: 30,
			maxWidth: 80,
			spacing: 2.0,
			visible: false
		) { _, _ in EmptyView() }
		#expect(col.name == "Battery Level")
		#expect(col.abbreviatedName == "Bat")
		#expect(col.minWidth == 30)
		#expect(col.maxWidth == 80)
		#expect(col.visible == false)
	}
}

// MARK: - Plottable floatValue extension

@Suite("Plottable floatValue")
struct PlottableFloatValueTests {

	@Test func intPlottable_hasFloatValue() {
		let val: Int = 42
		#expect(val.floatValue == 42.0)
	}

	@Test func doublePlottable_hasFloatValue() {
		let val: Double = 3.14
		// Float precision
		#expect(val.floatValue != nil)
		#expect(abs((val.floatValue ?? 0) - 3.14) < 0.01)
	}

	@Test func intPlottable_hasDoubleValue() {
		let val: Int = 100
		#expect(val.doubleValue == 100.0)
	}

	@Test func doublePlottable_hasDoubleValue() {
		let val: Double = 99.9
		#expect(val.doubleValue == 99.9)
	}

	@Test func floatPlottable_hasFloatValue() {
		let val: Float = 1.5
		#expect(val.floatValue == 1.5)
	}
}
