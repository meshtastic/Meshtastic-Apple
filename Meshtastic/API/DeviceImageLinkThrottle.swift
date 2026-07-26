//
//  DeviceImageLinkThrottle.swift
//  Meshtastic
//
//  Created by Brian Ruschill on 7/25/26.
//

import Foundation
import os

/// Serializes the device image/link refresh throttle against database clears.
///
/// Two paths write `UserDefaults.lastDeviceImageAndLinkUpdate` and they can interleave:
///
/// - `MeshtasticAPI.refreshDeviceImagesAndLinks()` runs detached from BLE connect Step 3b and
///   records completion when it finishes, which may be many seconds later.
/// - `clearDatabase` (both `PersistenceController` and `MeshPackets`) wipes the
///   `DeviceHardwareImageEntity`/`DeviceLinkEntity` rows that pass populates, and invalidates the
///   throttle so the next connect restores them.
///
/// Without coordination a pass that started *before* a clear can finish *after* it and overwrite
/// the invalidation with `Date()`. The rows are gone but the throttle reads "refreshed recently",
/// so Step 3b skips the restore and the device catalog stays imageless for the rest of the 48h
/// window — exactly the failure the reset exists to prevent.
///
/// Each clear bumps a generation. A pass captures the generation it started under via
/// ``beginIfStale(interval:)`` and only records completion if that generation is still current,
/// so a superseded pass silently drops its write and leaves the restore armed.
enum DeviceImageLinkThrottle {

	/// Guards the generation counter *and* the timestamp together. Both the freshness check and
	/// the completion write are compare-and-act sequences; holding the lock across each is what
	/// makes them atomic with respect to an intervening `invalidate()`. The critical sections are
	/// a `UserDefaults` read/write and an integer compare — short enough for an unfair lock.
	private static let state = OSAllocatedUnfairLock(initialState: 0)

	/// Claims a pass if the last one is older than `interval`, returning the token to complete with.
	///
	/// Returns `nil` when a pass completed inside the window, meaning the caller should skip. The
	/// freshness check and the token capture happen under one lock acquisition so a clear cannot
	/// land between them and hand back a token that is already stale.
	static func beginIfStale(interval: TimeInterval) -> Int? {
		state.withLock { generation in
			let last = UserDefaults.lastDeviceImageAndLinkUpdate
			guard last == .distantPast || abs(last.timeIntervalSinceNow) > interval else {
				return nil
			}
			return generation
		}
	}

	/// Records a completed pass, unless a clear superseded it.
	///
	/// A mismatched token means `invalidate()` ran while this pass was in flight, so the rows it
	/// just wrote are gone. Dropping the write leaves the timestamp at `.distantPast` and lets the
	/// next connect run a real restore.
	static func complete(token: Int) {
		state.withLock { generation in
			guard generation == token else { return }
			UserDefaults.lastDeviceImageAndLinkUpdate = Date()
		}
	}

	/// Forces the next pass to run, and supersedes any pass already in flight.
	///
	/// Called by `clearDatabase` after wiping the image/link rows.
	static func invalidate() {
		state.withLock { generation in
			generation &+= 1
			UserDefaults.lastDeviceImageAndLinkUpdate = .distantPast
		}
	}
}
