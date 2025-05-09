//
//  RateLimitCountdownView.swift
//  Meshtastic
//
//  Created by Jake Bordens on 5/5/25.
//

import SwiftUI

// This class provides a rate limited button.
// Provide a key to differentiate which action is rate-limited
// This allows you to keep different rate limits for different action
// Rate limits are stored in a RateLimitStorage singleton, but do not persist
public struct RateLimitedButton<Content: View>: View {
	typealias Builder = ((percentComplete: Double, secondsRemaining: TimeInterval)?) -> Content

	let key: String

	@StateObject var storage = RateLimitStorage.shared

	let rateLimit: TimeInterval
	let content: Builder
	let action: () -> Void

	init(key: String, rateLimit: TimeInterval, action: @escaping () -> Void, @ViewBuilder label: @escaping Builder) {
		self.key = key
		self.rateLimit = rateLimit
		self.content = label
		self.action = action
	}

	public var body: some View {
		let percentRemaining = storage.rateLimitRemainingPercentage(forKey: key)
		let secondsRemaining = storage.rateLimitSecondsRemaining(forKey: key)
		if  percentRemaining > 0.0 {
			content((percentRemaining, secondsRemaining))
		} else {
			Button {
				storage.actionOccured(forKey: key, rateLimit: rateLimit)
				action()
			} label: {
				content(nil)
			}
		}
	}
}

// To store the time an action occured (name by a key) and the time limit
// Does not persist across app launches
class RateLimitStorage: ObservableObject {
	private struct RateLimiter {
		var actionOccuredTimestamp: Date
		var rateLimitSeconds: TimeInterval

		var rateLimitExpires: Date {
			return actionOccuredTimestamp.addingTimeInterval(rateLimitSeconds)
		}
	}

	static var shared: RateLimitStorage = RateLimitStorage() // Singleton instance

	private var rateLimits = [String: RateLimiter]()
	private var timer: Timer?

	func actionOccured(forKey key: String, rateLimit: TimeInterval) {
		let now = Date()
		if let existingRateLimit = rateLimits[key] {
			if existingRateLimit.rateLimitExpires > now.addingTimeInterval(rateLimit) {
				// We have an existing rate limit that is larger than the one being requested
				// Ignore
				return
			}
		}
		self.objectWillChange.send()
		rateLimits[key] = RateLimiter(actionOccuredTimestamp: now, rateLimitSeconds: rateLimit)
		startTimerIfNecessary()
	}

	func rateLimitRemainingPercentage(forKey: String) -> Double {
		guard let rateLimit = rateLimits[forKey] else {
			return 0.0
		}
		let percent = (rateLimit.rateLimitExpires.timeIntervalSinceNow) / rateLimit.rateLimitSeconds
		return min(1.0, max(percent, 0.0))
	}

	func rateLimitSecondsRemaining(forKey: String) -> TimeInterval {
		guard let rateLimit = rateLimits[forKey] else {
			return 0.0
		}
		return rateLimit.rateLimitExpires.timeIntervalSinceNow
	}

	func startTimerIfNecessary() {
		// Timer exists, don't create one
		guard timer == nil else { return }

		// Create the timer
		self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			guard let self = self else { return }
			self.objectWillChange.send()

			// Determine if we can clean up the dictionary and stop the timer.
			let maxExpiration = self.rateLimits.values.map { $0.rateLimitExpires }.max() ?? .distantPast
			if maxExpiration.timeIntervalSinceNow < 0 {
				// All rateLimits are in the past.  Stop and clean up
				self.timer?.invalidate()
				self.timer = nil
				self.rateLimits.removeAll()
			}
		}
	}
}
