//
//  PacketStreamModel.swift
//  Meshtastic
//
//  Live tail of over-the-air mesh packet traffic for the debug log viewer.
//  Reads the unified OSLog store (Mesh category only) incrementally, paces the
//  reveal of new entries to a human-readable rate, and bounds memory.
//
//  Created for spec 012-packet-stream-log-filter.
//

import Foundation
@preconcurrency import OSLog
import SwiftUI

@MainActor
final class PacketStreamModel: ObservableObject {

	/// Entries currently shown in the stream, chronological (newest last). Capped at `maxVisible`.
	@Published private(set) var visibleEntries: [OSLogEntryLog] = []
	/// Whether the live tail is running.
	@Published private(set) var isStreaming = false
	/// When true, new entries auto-scroll into view; set false while the user reads back.
	@Published var isPinnedToLiveEdge = true
	/// True once sustained overload has forced us to drop un-revealed packets.
	@Published private(set) var droppedDueToOverload = false

	// MARK: - Tuning

	/// ≈2 entries/sec at calm and ≈6 entries/sec under load (SC-008). The 500ms tick
	/// keeps main-actor churn low; the adaptive per-tick count catches up a backlog without
	/// the stream becoming unreadable.
	private let revealIntervalNanos: UInt64 = 500_000_000
	/// Poll cadence for new entries (well under the 5s visibility target, SC-001).
	private let pollIntervalNanos: UInt64 = 1_000_000_000

	private let meshCategory = "🕸️ Mesh"
	private let subsystem = Bundle.main.bundleIdentifier ?? "gvh.MeshtasticClient"

	// MARK: - State

	/// Holds the visible (capped at 1,000 — FR-011) and pending (capped at 120, drop-oldest —
	/// favor most-recent, R3) buffers plus the reveal/cap math. Extracted for unit testing.
	private var buffer = PacketStreamBuffer<OSLogEntryLog>(maxVisible: 1_000, maxPending: 120)
	private var lastSeenDate: Date?
	/// Keys of entries seen at exactly `lastSeenDate`, for boundary de-dup (R1: `position(date:)`
	/// is second-granular and inclusive).
	private var boundaryKeys: Set<String> = []

	private var pollTask: Task<Void, Never>?
	private var revealTask: Task<Void, Never>?

	/// Mesh-only predicate, all levels (FR-002 override).
	var predicateFormat: String {
		"subsystem == \"\(subsystem)\" AND category == \"\(meshCategory)\""
	}

	// MARK: - Lifecycle

	func start() {
		guard !isStreaming else { return }
		isStreaming = true
		pollTask = Task { [weak self] in await self?.runPollLoop() }
		revealTask = Task { [weak self] in await self?.runRevealLoop() }
	}

	func stop() {
		pollTask?.cancel()
		pollTask = nil
		revealTask?.cancel()
		revealTask = nil
		isStreaming = false
	}

	func reset() {
		stop()
		buffer.clear()
		visibleEntries = []
		lastSeenDate = nil
		boundaryKeys = []
		droppedDueToOverload = false
		isPinnedToLiveEdge = true
	}

	func setPinned(_ pinned: Bool) {
		isPinnedToLiveEdge = pinned
	}

	/// Full Mesh-category log for export (FR-024 / Edge: Sharing) — not truncated to the
	/// on-screen display cap.
	func fetchAllForExport() async -> [OSLogEntryLog] {
		(try? await Logger.fetch(predicateFormat: predicateFormat)) ?? []
	}

	// MARK: - Polling

	private func runPollLoop() async {
		// Backfill from boot only on a cold start; when resuming (toggled off/on,
		// returned to the screen, or foregrounded) continue from the last-seen cursor
		// so accumulated entries are kept and not duplicated.
		await poll(initial: lastSeenDate == nil)
		while !Task.isCancelled {
			try? await Task.sleep(nanoseconds: pollIntervalNanos)
			if Task.isCancelled { return }
			await poll(initial: false)
		}
	}

	/// Fetch newly arrived Mesh entries and enqueue them. The initial pass backfills recent
	/// history straight into the visible buffer (no pacing); later passes feed the paced queue.
	func poll(initial: Bool) async {
		let since = initial ? nil : lastSeenDate
		let fetched = (try? await Logger.fetch(predicateFormat: predicateFormat, since: since)) ?? []
		guard !fetched.isEmpty else { return }

		var accepted: [OSLogEntryLog] = []
		for log in fetched {
			if !initial, let lastSeenDate {
				if log.date < lastSeenDate { continue }
				if log.date == lastSeenDate, boundaryKeys.contains(Self.entryKey(log)) { continue }
			}
			accepted.append(log)
		}
		guard !accepted.isEmpty else { return }

		advanceBoundary(with: accepted)

		if initial {
			buffer.appendVisible(accepted)
		} else {
			buffer.enqueue(accepted)
		}
		syncFromBuffer()
	}

	private func advanceBoundary(with accepted: [OSLogEntryLog]) {
		guard let newMax = accepted.map(\.date).max() else { return }
		let keysAtMax = Set(accepted.filter { $0.date == newMax }.map(Self.entryKey))
		if newMax == lastSeenDate {
			boundaryKeys.formUnion(keysAtMax)
		} else {
			lastSeenDate = newMax
			boundaryKeys = keysAtMax
		}
	}

	// MARK: - Reveal pacing

	private func runRevealLoop() async {
		while !Task.isCancelled {
			try? await Task.sleep(nanoseconds: revealIntervalNanos)
			if Task.isCancelled { return }
			revealTick()
		}
	}

	/// Adaptive reveal: a gentle ~6/sec when traffic is calm and readable, scaling up
	/// per tick as the pending backlog grows so a burst (or a fast replay) scrolls quickly
	/// and catches up instead of crawling. Pacing throttles only the reveal, never
	/// ingestion (FR-021/FR-022).
	func revealTick() {
		let perTick: Int
		switch buffer.pending.count {
		case 0:       perTick = 0
		case 1...10:  perTick = 1    // ~2/sec  — calm, easy to read
		case 11...40: perTick = 3    // ~6/sec  — spec target SC-008
		default:      perTick = 6    // ~12/sec — drain backlog quickly
		}
		if perTick > 0, buffer.reveal(perTick) > 0 { syncFromBuffer() }
	}

	private func syncFromBuffer() {
		visibleEntries = buffer.visible
		droppedDueToOverload = buffer.droppedDueToOverload
	}

	static func entryKey(_ log: OSLogEntryLog) -> String {
		"\(log.date.timeIntervalSince1970)|\(log.composedMessage)"
	}
}

/// Bounded two-stage buffer backing the packet stream: a paced `pending` queue feeding a
/// capped `visible` window. Generic + value-type so the reveal/cap rules are unit-testable
/// without un-constructible `OSLogEntryLog` instances.
struct PacketStreamBuffer<Element> {
	private(set) var visible: [Element] = []
	private(set) var pending: [Element] = []
	private(set) var droppedDueToOverload = false
	let maxVisible: Int
	let maxPending: Int

	init(maxVisible: Int, maxPending: Int) {
		self.maxVisible = maxVisible
		self.maxPending = maxPending
	}

	/// Append directly to the visible window (e.g. initial backfill), enforcing the cap.
	mutating func appendVisible(_ items: [Element]) {
		visible.append(contentsOf: items)
		trimVisible()
	}

	/// Queue newly-arrived items for paced reveal; drop oldest beyond the pending cap (FR-022).
	mutating func enqueue(_ items: [Element]) {
		pending.append(contentsOf: items)
		if pending.count > maxPending {
			pending.removeFirst(pending.count - maxPending)
			droppedDueToOverload = true
		}
	}

	/// Move up to `count` items from pending into the visible window. Returns how many moved.
	@discardableResult
	mutating func reveal(_ count: Int) -> Int {
		guard !pending.isEmpty, count > 0 else { return 0 }
		let n = min(count, pending.count)
		let batch = Array(pending.prefix(n))
		pending.removeFirst(n)
		appendVisible(batch)
		return n
	}

	mutating func clear() {
		visible = []
		pending = []
		droppedDueToOverload = false
	}

	private mutating func trimVisible() {
		if visible.count > maxVisible {
			visible.removeFirst(visible.count - maxVisible)
		}
	}
}
