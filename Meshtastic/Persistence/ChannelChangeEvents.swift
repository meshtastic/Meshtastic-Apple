//
//  ChannelChangeEvents.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import os
import SwiftData

/// The channel-change rows in a radio's conversations (feature 021, T377).
///
/// A channel slot keeps its conversation when the radio moves it to another channel: a new modem
/// preset, name, key or mesh. Each change leaves a row in the radio's thread for the slot,
/// between the messages before and after it, so the history before a change reads as what it
/// was.
enum ChannelChangeEvents {
	/// A change undone within this many seconds removes its row, and a further change extends it:
	/// a radio sending its settings can pass through a channel briefly (T377).
	static let coalesceWindow: Int32 = 60

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
	///
	/// No row when the slot's latest row already ends on `key`: the slot's history says it's on
	/// that channel, so `previous` is a stale copy (a long-lived context that missed the save
	/// that recorded the change), not a second change.
	@discardableResult
	static func record(radio: Int64, slot: Int32, from previous: String, to key: String, in context: ModelContext, now: Date = Date()) throws -> Int {
		guard previous != key, !isPaused(radio: radio) else { return 0 }
		let timestamp = Int32(clamping: Int64(now.timeIntervalSince1970))
		let latest = try latestEvent(radio: radio, slot: slot, in: context)
		if latest?.channelKey == key {
			return 0
		}
		if let latest,
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
		row.receivedBy = ReceivedBy.adding(radio, to: "")
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
}
