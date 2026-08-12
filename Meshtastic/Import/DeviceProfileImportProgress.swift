//
//  DeviceProfileImportProgress.swift
//  Meshtastic
//
//  Pure model for tracking per-item progress during a device-profile import run. Fed by the importer's
//  progress callback; exposes the fraction completed, the current item, and per-section status for
//  the view layer. No SwiftUI or device dependency.
//

import Foundation

/// Tracks the progress of an in-flight import run as the importer's progress callback fires.
///
/// Designed to be driven solely by the `(item, index, total)` callback from
/// `DeviceProfileImporter.apply`. The importer reorders items (MQTT/Serial are deferred to after the
/// transaction commit), so the progress index is a GLOBAL index into the flattened send order, NOT a
/// plan-order index. This model accumulates state from the callbacks themselves and does not depend on
/// plan-order assumptions.
struct ImportApplyProgress {
	/// Per-section item count for the active selection. Used only to determine when a section is fully
	/// announced (all its items have been seen and none is currently in flight).
	private let sectionItemCounts: [ImportSection: Int]

	/// Sections that have been announced (at least one item seen).
	private var sectionAnnouncedCounts: [ImportSection: Int] = [:]

	/// The section of the item currently in flight (the most recently announced item).
	private(set) var currentSection: ImportSection?

	/// Display name of the item currently in flight.
	private(set) var currentItemTitle: String = ""

	/// The global zero-based index of the current in-flight item.
	private(set) var currentIndex: Int = 0

	/// Total items in this run.
	let total: Int

	/// One-based index for display ("Sending 3 of 12").
	var currentIndexOneBased: Int { currentIndex + 1 }

	/// Fraction of the run that has been announced. While item `i` is in flight, `i` items (indices
	/// 0..<i) have been sent. So fractionCompleted = Double(i) / Double(total). After the last item
	/// is announced (index == total-1), fraction is (total-1)/total; the run is not 1.0 until the
	/// importer finishes and the view clears the model.
	var fractionCompleted: Double {
		guard total > 0 else { return 0 }
		return Double(currentIndex) / Double(total)
	}

	/// Status of a section in the import run.
	enum SectionStatus {
		/// No item from this section has been announced yet.
		case pending
		/// The currently in-flight item belongs to this section.
		case sending
		/// Every item belonging to this section has been announced AND none is currently in flight.
		///
		/// NOTE: A section whose items are split across the transactional and post-commit phases (e.g.
		/// Modules, which contains both transactional items and deferred MQTT/Serial) reads `.pending`
		/// between its phases: once its transactional items are sent and another section is in flight,
		/// `announced < expected` with no current item in the section, so the section is genuinely
		/// waiting again — sending -> pending -> sending. It only becomes `.sent` after its last
		/// deferred item has been announced and a later item (or none) is current.
		case sent
	}

	/// - Parameter sectionItemCounts: number of items per section in the active selection. Sections
	///   with zero items are ignored. Derive this from `DeviceProfileImportPlan.items(for:)`.
	init(sectionItemCounts: [ImportSection: Int]) {
		self.sectionItemCounts = sectionItemCounts.filter { $0.value > 0 }
		self.total = sectionItemCounts.values.reduce(0, +)
	}

	/// Record a progress callback from the importer.
	///
	/// - Parameters:
	///   - item: the import item about to be sent.
	///   - index: zero-based global index in the send order.
	///   - total: total number of items in the run.
	mutating func announce(item: ImportItem, index: Int, total: Int) {
		assert(total == self.total, "importer total (\(total)) diverged from model total (\(self.total))")
		currentSection = item.section
		currentItemTitle = item.kind.displayName
		currentIndex = index

		// Track how many items from this section have been announced.
		sectionAnnouncedCounts[item.section, default: 0] += 1
	}

	/// Returns the status of a section during the import run.
	func sectionStatus(_ section: ImportSection) -> SectionStatus {
		guard let expected = sectionItemCounts[section], expected > 0 else {
			return .pending
		}
		let announced = sectionAnnouncedCounts[section, default: 0]
		// Is the current in-flight item in this section?
		let isCurrent = currentSection == section
		if isCurrent {
			return .sending
		}
		if announced >= expected {
			return .sent
		}
		return .pending
	}
}
