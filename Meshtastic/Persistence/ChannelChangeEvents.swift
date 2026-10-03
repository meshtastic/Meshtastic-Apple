//
//  ChannelChangeEvents.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import os
import SwiftData

/// The channel-change rows in a radio's conversations (feature 021, T377/T378).
///
/// A channel slot keeps its conversation when the radio moves it to another channel: a new modem
/// preset, name, key or mesh. That's what a radio's slot always did with one radio, and it's how
/// the history before a change stays readable after it. Each change leaves a row in that radio's
/// thread for the slot, between the messages before and after it, and the rows are what the
/// thread's time segments (`segments`) are built from: before a change the slot showed the old
/// channel's messages, after it the new channel's.
enum ChannelChangeEvents {
	/// A change undone within this many seconds removes its row, and a further change extends it:
	/// a radio sending its settings can pass through a channel briefly (T377).
	static let coalesceWindow: Int32 = 60
	/// The most recent changes a thread follows. Older ones still have their rows; the oldest
	/// segment then starts at the beginning of the history.
	static let maxSegments = 32

	/// One stretch of a radio's thread for a slot: the channel `key`'s messages from `start`
	/// (inclusive) to `end` (exclusive), in `messageTimestamp` seconds. Nil is unbounded.
	struct Segment: Equatable, Sendable {
		let key: String
		let start: Int32?
		let end: Int32?

		/// The same channel's `c1` key, for rows stored before the mesh was part of the key and
		/// not yet converted (`MultiRadioBackfill.rekeyLegacyMessages`).
		var legacyKey: String? {
			guard let parts = ChannelIdentity.parts(of: key) else { return nil }
			return "\(ChannelIdentity.legacyKeyVersion):\(parts.keyDigest):\(parts.name)"
		}
	}

	// MARK: - Pausing

	/// Radios whose channel changes aren't recorded for now: Local Mesh Discovery steps a radio
	/// through presets and puts its own back, which isn't the user moving the slot (T377).
	private static let pausedRadios = OSAllocatedUnfairLock<Set<Int64>>(initialState: [])

	static func pause(radio: Int64) {
		pausedRadios.withLock { _ = $0.insert(radio) }
	}

	static func resume(radio: Int64) {
		pausedRadios.withLock { _ = $0.remove(radio) }
	}

	static func isPaused(radio: Int64) -> Bool {
		pausedRadios.withLock { $0.contains(radio) }
	}

	// MARK: - Recording

	/// Records that `radio` moved slot `slot` from channel `previous` to `key`. Returns 1 when a
	/// row was written, changed or removed, 0 otherwise. Doesn't save.
	@discardableResult
	static func record(radio: Int64, slot: Int32, from previous: String, to key: String, in context: ModelContext, now: Date = Date()) throws -> Int {
		guard previous != key, !isPaused(radio: radio) else { return 0 }
		let timestamp = Int32(clamping: Int64(now.timeIntervalSince1970))
		if let latest = try latestEvent(radio: radio, slot: slot, in: context),
		   latest.channelKey == previous,
		   timestamp - latest.messageTimestamp < coalesceWindow {
			if latest.previousChannelKey == key {
				// Back where it started: there was no change.
				context.delete(latest)
			} else {
				latest.channelKey = key
			}
			return 1
		}
		let row = MessageEntity()
		row.systemEvent = MessageEntity.SystemEvent.channelChanged.rawValue
		// Negative ids never clash with a packet id; the message lists key their rows on the id.
		row.messageId = -Int64.random(in: 1...Int64(Int32.max))
		row.messageKey = "event:\(UUID().uuidString)"
		row.messageTimestamp = timestamp
		row.channel = slot
		row.channelKey = key
		row.previousChannelKey = previous
		row.localNodeNum = radio
		// Not from anyone. A set `fromNum` also tells the backfill the row needs nothing.
		row.fromNum = 0
		row.toNum = MultiRadioBackfill.broadcastNum
		row.read = true
		row.messagePayload = ""
		context.insert(row)
		return 1
	}

	/// The most recent change row for `radio`'s slot `slot`.
	static func latestEvent(radio: Int64, slot: Int32, in context: ModelContext) throws -> MessageEntity? {
		let eventRaw = MessageEntity.SystemEvent.channelChanged.rawValue
		let radioNum: Int64? = radio
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate { $0.systemEvent == eventRaw && $0.localNodeNum == radioNum && $0.channel == slot },
			sortBy: [SortDescriptor(\.messageTimestamp, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try context.fetch(descriptor).first
	}

	// MARK: - Segments

	/// The stretches of `radio`'s thread for slot `slot`, oldest first, ending with `currentKey`'s.
	/// One unbounded segment when the slot never changed.
	static func segments(radio: Int64, slot: Int32, currentKey: String, in context: ModelContext) -> [Segment] {
		let eventRaw = MessageEntity.SystemEvent.channelChanged.rawValue
		let radioNum: Int64? = radio
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate { $0.systemEvent == eventRaw && $0.localNodeNum == radioNum && $0.channel == slot },
			sortBy: [SortDescriptor(\.messageTimestamp, order: .reverse)]
		)
		descriptor.fetchLimit = maxSegments
		let events = ((try? context.fetch(descriptor)) ?? []).reversed().map {
			Event(timestamp: $0.messageTimestamp, previous: $0.previousChannelKey, key: $0.channelKey)
		}
		return segments(events: events, currentKey: currentKey)
	}

	/// What `segments` needs from a change row.
	struct Event: Equatable {
		let timestamp: Int32
		let previous: String?
		let key: String?
	}

	/// `segments` from change rows already read, oldest first. Separate for testing.
	static func segments(events: [Event], currentKey: String) -> [Segment] {
		guard let first = events.first else {
			return [Segment(key: currentKey, start: nil, end: nil)]
		}
		var result: [Segment] = []
		if let previous = first.previous {
			result.append(Segment(key: previous, start: nil, end: first.timestamp))
		}
		for (index, event) in events.enumerated() {
			let end = index + 1 < events.count ? events[index + 1].timestamp : nil
			// The last stretch is the slot's channel now, whatever the last row says.
			let key = end == nil ? currentKey : (event.key ?? currentKey)
			result.append(Segment(key: key, start: event.timestamp, end: end))
		}
		return result
	}
}
