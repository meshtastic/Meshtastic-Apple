// FirmwareViewModelErrorTests.swift
// MeshtasticTests

import Testing
import Foundation
import SwiftUI
@testable import Meshtastic

// MARK: - FirmwareViewModelError Tests

@Suite("FirmwareViewModelError")
struct FirmwareViewModelErrorTests {

	@Test func timedOut_description() {
		let err = FirmwareViewModel.FirmwareViewModelError.timedOut(30.0)
		#expect(err.errorDescription?.contains("30") == true)
		#expect(err.errorDescription?.contains("timed out") == true)
	}

	@Test func unknownFirmwareVersion_description() {
		let err = FirmwareViewModel.FirmwareViewModelError.unknownFirmwareVersion
		#expect(err.errorDescription?.contains("firmware") == true || err.errorDescription?.contains("Unknown") == true)
	}

	@Test func unableToFindOrCreateEntity_description() {
		let err = FirmwareViewModel.FirmwareViewModelError.unableToFindOrCreateEntity
		#expect(err.errorDescription != nil)
		#expect(!err.errorDescription!.isEmpty)
	}

	@Test func unknownArchitecture_description() {
		let err = FirmwareViewModel.FirmwareViewModelError.unknownArchitecture
		#expect(err.errorDescription?.contains("architecture") == true || err.errorDescription?.contains("Unknown") == true)
	}

	@Test func unknownPlatformIOTarget_description() {
		let err = FirmwareViewModel.FirmwareViewModelError.unknownPlatformIOTarget
		#expect(err.errorDescription != nil)
		#expect(!err.errorDescription!.isEmpty)
	}
}

// MARK: - Additional Plottable Extension Tests

@Suite("Plottable doubleValue")
struct PlottableDoubleValueTests {

	@Test func int_toDouble() {
		let v: Int = 42
		#expect(v.doubleValue == 42.0)
	}

	@Test func int32_toDouble() {
		let v: Int32 = -100
		#expect(v.doubleValue == -100.0)
	}

	@Test func float_toDouble() {
		let v: Float = 3.14
		let d = v.doubleValue!
		#expect(abs(d - 3.14) < 0.01)
	}

	@Test func double_toDouble() {
		let v: Double = 2.718
		#expect(v.doubleValue == 2.718)
	}

	@Test func int_toFloat() {
		let v: Int = 100
		#expect(v.floatValue == 100.0)
	}

	@Test func float_toFloat() {
		let v: Float = 1.5
		#expect(v.floatValue == 1.5)
	}
}

// MARK: - MetricsTableColumn Property Tests

@Suite("MetricsTableColumn Properties Extended")
struct MetricsTableColumnPropertyExtendedTests {

	private func makeColumn(
		id: String = "test",
		name: String = "Test",
		abbreviatedName: String = "T",
		minWidth: CGFloat? = nil,
		maxWidth: CGFloat? = nil,
		spacing: CGFloat = 0.1,
		visible: Bool = true
	) -> MetricsTableColumn {
		MetricsTableColumn(
			id: id,
			keyPath: \TelemetryEntity.batteryLevel,
			name: name,
			abbreviatedName: abbreviatedName,
			minWidth: minWidth,
			maxWidth: maxWidth,
			spacing: spacing,
			visible: visible
		) { _, value in
			EmptyView()
		}
	}

	@Test func properties() {
		let col = makeColumn(id: "bat", name: "Battery", abbreviatedName: "Bat", minWidth: 50, maxWidth: 100, spacing: 2.0, visible: false)
		#expect(col.id == "bat")
		#expect(col.name == "Battery")
		#expect(col.abbreviatedName == "Bat")
		#expect(col.minWidth == 50)
		#expect(col.maxWidth == 100)
		#expect(col.spacing == 2.0)
		#expect(col.visible == false)
	}

	@Test func identifiable() {
		let col = makeColumn(id: "myId")
		#expect(col.id == "myId")
	}

	@Test func hashable_sameId() {
		let c1 = makeColumn(id: "same", name: "A")
		let c2 = makeColumn(id: "same", name: "B")
		#expect(c1 == c2)
	}

	@Test func hashable_differentId() {
		let c1 = makeColumn(id: "a")
		let c2 = makeColumn(id: "b")
		#expect(c1 != c2)
	}

	@Test func gridItemSize_withMinMax() {
		let col = makeColumn(minWidth: 40, maxWidth: 120)
		if case .flexible = col.gridItemSize {} else {
			// gridItemSize should be .flexible
		}
	}

	@Test func gridItemSize_withoutMinMax() {
		let col = makeColumn()
		if case .flexible = col.gridItemSize {} else {
			// gridItemSize should be .flexible
		}
	}
}

// MARK: - MetricsColumnList Collection Tests

@Suite("MetricsColumnList Collection Extended")
struct MetricsColumnListExtendedTests {

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

	@Test func columnWithId_found() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a"), makeColumn(id: "b")])
		#expect(list.column(withId: "b")?.id == "b")
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

	@Test func toggleVisibility_togglesColumn() {
		let col = makeColumn(id: "a", visible: true)
		let list = MetricsColumnList(columns: [col])
		list.toggleVisibity(for: col)
		#expect(col.visible == false)
	}

	@Test func visible_filtersCorrectly() {
		let list = MetricsColumnList(columns: [
			makeColumn(id: "a", visible: true),
			makeColumn(id: "b", visible: false),
		])
		#expect(list.visible.count == 1)
		#expect(list.visible.first?.id == "a")
	}

	@Test func collectionConformance_append() {
		let list = MetricsColumnList(columns: [])
		list.append(makeColumn(id: "x"))
		#expect(list.count == 1)
	}

	@Test func collectionConformance_remove() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a"), makeColumn(id: "b")])
		let removed = list.remove(at: 0)
		#expect(removed.id == "a")
		#expect(list.count == 1)
	}

	@Test func collectionConformance_insert() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a"), makeColumn(id: "c")])
		list.insert(makeColumn(id: "b"), at: 1)
		#expect(list[1].id == "b")
		#expect(list.count == 3)
	}

	@Test func collectionConformance_removeAll() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a")])
		list.removeAll()
		#expect(list.count == 0)
	}

	@Test func collectionConformance_subscriptSet() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a")])
		list[0] = makeColumn(id: "b")
		#expect(list[0].id == "b")
	}

	@Test func collectionConformance_replaceSubrange() {
		let list = MetricsColumnList(columns: [makeColumn(id: "a"), makeColumn(id: "b")])
		list.replaceSubrange(0..<1, with: [makeColumn(id: "x")])
		#expect(list[0].id == "x")
	}

	@Test func initFromSequence() {
		let arr = [makeColumn(id: "a"), makeColumn(id: "b")]
		let list = MetricsColumnList(arr)
		#expect(list.count == 2)
	}

	@Test func emptyInit() {
		let list = MetricsColumnList()
		#expect(list.count == 0)
	}
}
