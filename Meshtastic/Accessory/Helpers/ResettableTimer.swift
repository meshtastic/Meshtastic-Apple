//
//  ResettableTimer.swift
//  Meshtastic
//
//  Created by jake on 8/16/25.
//

import Foundation  // For Duration and Task (though often implicit in Swift environments)
import OSLog

/// A resettable timer implemented using Swift concurrency.
/// The timer can optionally be set to repeat, executing the closure repeatedly at the specified interval.
/// Calling `reset` cancels any ongoing timer and starts a new one with the given delay.
/// For repeating timers, it will continue firing until explicitly cancelled.
actor ResettableTimer {
	private var currentTask: Task<Void, Never>?
	private let action: @Sendable () async -> Void
	private let isRepeating: Bool
	private let debugName: String?
	/// Initializes the timer with the closure to execute and whether it should repeat.
	/// - Parameters:
	///   - isRepeating: If true, the timer will repeat indefinitely until cancelled. Defaults to false for one-shot behavior.
	///   - action: The closure to run after the delay elapses (and repeatedly if repeating).
	init(isRepeating: Bool = false, debugName: String? = nil, action: @Sendable @escaping () async -> Void) {
		self.isRepeating = isRepeating
		self.action = action
		self.debugName = debugName
	}
	
	/// Resets the timer to a new delay, cancelling any previous scheduled execution.
	/// - Parameter delay: The new delay duration before executing the action.
	func reset(delay: Duration, withReason reason: String? = nil) {
		if let debugName {
			if let reason {
				Logger.services.debug("⏱️ [\(debugName)] Resettable timer reset with new duration \(delay): \(reason)")
			} else {
				Logger.services.debug("⏱️ [\(debugName)] Resettable timer reset with new duration \(delay)")
			}
		}
		currentTask?.cancel()
		currentTask = Task {
			repeat {
				do {
					try await Task.sleep(for: delay)
					if Task.isCancelled { break }
					await action()
				} catch {
					// Timer was cancelled or sleep interrupted; exit the loop.
					break
				}
			} while isRepeating
		}
	}
	
	/// Cancels the timer without starting a new one. For repeating timers, this stops future executions.
	func cancel(withReason reason: String? = nil) {
		if let debugName {
			if let reason {
				Logger.services.debug("⏱️ [\(debugName)] Resettable timer cancelled: \(reason)")
			} else {
				Logger.services.debug("⏱️ [\(debugName)] Resettable timer cancelled")
			}
		}
		currentTask?.cancel()
		currentTask = nil
	}
}
