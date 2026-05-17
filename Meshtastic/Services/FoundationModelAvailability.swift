// MARK: FoundationModelAvailability
//
//  FoundationModelAvailability.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

/// App-wide singleton that tracks whether FoundationModels is usable on this device.
/// After the first "model not available" / "AI not enabled" / "asset not found" error,
/// it disables FM calls for a cooldown period (default 15 min) to stop console log spam
/// from repeated PrewarmSession / Model Catalog failures.
actor FoundationModelAvailability {

	static let shared = FoundationModelAvailability()

	/// How long to back off after a hard failure (seconds).
	private let cooldown: TimeInterval = 900 // 15 minutes

	/// Set when FM fails with a non-transient error.
	private var disabledUntil: Date?

	/// Prevents duplicate log lines during a single cooldown window.
	private var hasLoggedCooldown = false

	private init() {}

	// MARK: - Public API

	/// Returns `true` if FM should be attempted right now.
	var isAvailable: Bool {
		guard let until = disabledUntil else { return true }
		if Date() >= until {
			disabledUntil = nil
			hasLoggedCooldown = false
			return true
		}
		if !hasLoggedCooldown {
			Logger.services.info("FoundationModels disabled until \(until.ISO8601Format(), privacy: .public) — skipping call")
			hasLoggedCooldown = true
		}
		return false
	}

	/// Call this when a FM invocation throws a non-transient error
	/// (model not available, AI not enabled, asset not found, etc.).
	func reportFailure(_ error: Error) {
		let desc = error.localizedDescription.lowercased()
		let isHardFailure = desc.contains("model") && desc.contains("not available")
			|| desc.contains("not enabled")
			|| desc.contains("not found in model catalog")
			|| desc.contains("asset") && desc.contains("not found")
		guard isHardFailure else { return }

		disabledUntil = Date().addingTimeInterval(cooldown)
		hasLoggedCooldown = false
		Logger.services.warning("FoundationModels hard failure — disabling for \(Int(self.cooldown))s: \(error.localizedDescription, privacy: .public)")
	}

	/// Manually reset (e.g. user taps "Re-run Analysis").
	func reset() {
		disabledUntil = nil
		hasLoggedCooldown = false
	}
}
