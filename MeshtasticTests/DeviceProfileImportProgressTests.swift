//
//  DeviceProfileImportProgressTests.swift
//  Meshtastic
//
//  Tests for ImportApplyProgress, the pure model that tracks per-item and per-section progress during
//  an import run. Verifies fraction computation, one-based display index, section status transitions,
//  split-phase sections, mid-run stops, and empty selections.
//

import Foundation
import Testing
import MeshtasticProtobufs

@testable import Meshtastic

@Suite("Device profile import progress")
struct DeviceProfileImportProgressTests {

	// MARK: - Helpers

	/// Makes a minimal ImportItem with the given kind and section.
	private func makeItem(_ kind: ImportItemKind, section: ImportSection) -> ImportItem {
		ImportItem(kind: kind, section: section, summary: kind.displayName,
				   isSensitive: false, mayReboot: false,
				   payload: .ringtone(""))  // payload content is irrelevant for progress tracking
	}

	// MARK: - Fraction

	@Test("Fraction at first callback is 0/total")
	func fractionAtFirstCallback() {
		var model = ImportApplyProgress(sectionItemCounts: [.radioAndDevice: 3])
		let item = makeItem(.deviceConfig, section: .radioAndDevice)
		model.announce(item: item, index: 0, total: 3)
		#expect(model.fractionCompleted == 0.0 / 3.0)
	}

	@Test("Fraction at mid-run callback reflects items before current")
	func fractionAtMid() {
		var model = ImportApplyProgress(sectionItemCounts: [.radioAndDevice: 4])
		let items: [(ImportItemKind, Int)] = [
			(.deviceConfig, 0), (.displayConfig, 1), (.positionConfig, 2)
		]
		for (kind, idx) in items {
			model.announce(item: makeItem(kind, section: .radioAndDevice), index: idx, total: 4)
		}
		// At index 2, items 0 and 1 have been sent.
		#expect(model.fractionCompleted == 2.0 / 4.0)
	}

	@Test("Fraction at last callback is (total-1)/total, not 1.0")
	func fractionAtLastCallback() {
		var model = ImportApplyProgress(sectionItemCounts: [.radioAndDevice: 3])
		for i in 0..<3 {
			model.announce(item: makeItem(.deviceConfig, section: .radioAndDevice), index: i, total: 3)
		}
		// Last item (index 2) is still in flight -> fraction is 2/3, not 1.0.
		#expect(model.fractionCompleted == 2.0 / 3.0)
	}

	@Test("Empty selection produces zero fraction")
	func emptySelection() {
		let model = ImportApplyProgress(sectionItemCounts: [:])
		#expect(model.total == 0)
		#expect(model.fractionCompleted == 0)
	}

	// MARK: - Index display

	@Test("Zero-based index produces correct one-based display index")
	func oneBasedIndex() {
		var model = ImportApplyProgress(sectionItemCounts: [.modules: 5])
		let item = makeItem(.mqtt, section: .modules)
		model.announce(item: item, index: 0, total: 5)
		#expect(model.currentIndexOneBased == 1)
		model.announce(item: item, index: 3, total: 5)
		#expect(model.currentIndexOneBased == 4)
	}

	@Test("Current item title reflects the most recent announcement")
	func currentItemTitle() {
		var model = ImportApplyProgress(sectionItemCounts: [.radioAndDevice: 2])
		model.announce(item: makeItem(.deviceConfig, section: .radioAndDevice), index: 0, total: 2)
		#expect(model.currentItemTitle == ImportItemKind.deviceConfig.displayName)
		model.announce(item: makeItem(.displayConfig, section: .radioAndDevice), index: 1, total: 2)
		#expect(model.currentItemTitle == ImportItemKind.displayConfig.displayName)
	}

	// MARK: - Section status transitions

	@Test("Section transitions pending -> sending -> sent across a multi-item section")
	func multiItemSectionTransitions() {
		var model = ImportApplyProgress(sectionItemCounts: [
			.radioAndDevice: 2,
			.modules: 1
		])
		// Before any announcements, everything is pending.
		#expect(model.sectionStatus(.radioAndDevice) == .pending)
		#expect(model.sectionStatus(.modules) == .pending)

		// First item of radioAndDevice announced.
		model.announce(item: makeItem(.deviceConfig, section: .radioAndDevice), index: 0, total: 3)
		#expect(model.sectionStatus(.radioAndDevice) == .sending)
		#expect(model.sectionStatus(.modules) == .pending)

		// Second item of radioAndDevice announced.
		model.announce(item: makeItem(.displayConfig, section: .radioAndDevice), index: 1, total: 3)
		#expect(model.sectionStatus(.radioAndDevice) == .sending)
		#expect(model.sectionStatus(.modules) == .pending)

		// First (only) item of modules announced — radioAndDevice should now be sent.
		model.announce(item: makeItem(.telemetry, section: .modules), index: 2, total: 3)
		#expect(model.sectionStatus(.radioAndDevice) == .sent)
		#expect(model.sectionStatus(.modules) == .sending)
	}

	@Test("Single-item section goes pending -> sending -> sent")
	func singleItemSection() {
		var model = ImportApplyProgress(sectionItemCounts: [
			.owner: 1,
			.radioAndDevice: 1
		])
		#expect(model.sectionStatus(.owner) == .pending)

		model.announce(item: makeItem(.owner, section: .owner), index: 0, total: 2)
		#expect(model.sectionStatus(.owner) == .sending)

		model.announce(item: makeItem(.deviceConfig, section: .radioAndDevice), index: 1, total: 2)
		#expect(model.sectionStatus(.owner) == .sent)
		#expect(model.sectionStatus(.radioAndDevice) == .sending)
	}

	// MARK: - Split-phase section

	@Test("A section split across transactional and deferred phases goes sending -> pending -> sending")
	func splitPhaseSection() {
		// Modules contains both transactional items (e.g. telemetry) and deferred items (mqtt).
		// The importer sends transactional items first, then other sections, then deferred items.
		// sectionItemCounts should reflect ALL items for Modules in the selection.
		var model = ImportApplyProgress(sectionItemCounts: [
			.modules: 2,        // telemetry (transactional) + mqtt (deferred)
			.radioAndDevice: 1  // device config (transactional, between them)
		])

		// Phase 1: transactional telemetry announced.
		model.announce(item: makeItem(.telemetry, section: .modules), index: 0, total: 3)
		#expect(model.sectionStatus(.modules) == .sending)

		// Phase 2: device config announced — modules' current item is done, but only 1 of 2 announced.
		model.announce(item: makeItem(.deviceConfig, section: .radioAndDevice), index: 1, total: 3)
		// Modules: 1 announced, 2 expected, not current -> pending (not all announced yet).
		#expect(model.sectionStatus(.modules) == .pending)
		#expect(model.sectionStatus(.radioAndDevice) == .sending)

		// Phase 3: deferred mqtt announced — modules is sending again.
		model.announce(item: makeItem(.mqtt, section: .modules), index: 2, total: 3)
		#expect(model.sectionStatus(.modules) == .sending)
		// radioAndDevice: all announced (1/1) and not current -> sent.
		#expect(model.sectionStatus(.radioAndDevice) == .sent)
	}

	// MARK: - Mid-run stop

	@Test("A mid-run stop leaves later sections pending and does not crash")
	func midRunStop() {
		var model = ImportApplyProgress(sectionItemCounts: [
			.owner: 1,
			.radioAndDevice: 2,
			.modules: 1
		])
		// Only the first item is announced before the run stops (cancel or error).
		model.announce(item: makeItem(.owner, section: .owner), index: 0, total: 4)

		// Owner is still "sending" because it was the last announcement (the run stopped while
		// it was in flight). The view clears the model when the run ends, so this state is only
		// visible transiently.
		#expect(model.sectionStatus(.owner) == .sending)
		#expect(model.sectionStatus(.radioAndDevice) == .pending)
		#expect(model.sectionStatus(.modules) == .pending)

		// Accessing properties on a stopped model does not crash.
		#expect(model.fractionCompleted == 0.0 / 4.0)
		#expect(model.currentItemTitle == ImportItemKind.owner.displayName)
		#expect(model.currentIndexOneBased == 1)
	}

	@Test("An empty selection model does not crash on sectionStatus queries")
	func emptySelectionSectionStatus() {
		let model = ImportApplyProgress(sectionItemCounts: [:])
		#expect(model.sectionStatus(.owner) == .pending)
		#expect(model.sectionStatus(.modules) == .pending)
		#expect(model.fractionCompleted == 0)
	}

	// MARK: - Section not in selection

	@Test("A section not in the counts is always pending")
	func sectionNotInSelection() {
		var model = ImportApplyProgress(sectionItemCounts: [.owner: 1])
		model.announce(item: makeItem(.owner, section: .owner), index: 0, total: 1)
		// Security was never part of the selection, so it stays pending.
		#expect(model.sectionStatus(.security) == .pending)
	}
}
