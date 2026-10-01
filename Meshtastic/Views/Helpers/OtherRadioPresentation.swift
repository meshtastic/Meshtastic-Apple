//
//  OtherRadioPresentation.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation

/// Which of another radio's passphrase sheet and prompt the one window asks for (feature 021,
/// review V14 P3): one at a time, the passphrase sheet first, and only while the window presents
/// nothing and none of its own gates or sheets is up. One that's asked for but not up two seconds
/// later, lost behind a sheet the app opened further in, is asked for again.
struct OtherRadioPresentation: Equatable {
	private(set) var showsUnlockSheet = false
	private(set) var showsPrompt = false
	private var askedAt: ContinuousClock.Instant?

	/// How long after it's asked for one that isn't up is asked for again.
	static let retryAfter: Duration = .seconds(2)

	/// `unlockPending` and `promptPending`: the manager has a passphrase request or a prompt for
	/// another radio. `windowPresenting`: the window presents something, what this asked for
	/// included. `gateUp`: one of the window's own gates or sheets is up or asked for.
	mutating func update(unlockPending: Bool, promptPending: Bool, windowPresenting: Bool, gateUp: Bool, now: ContinuousClock.Instant) {
		if !unlockPending { showsUnlockSheet = false }
		if !promptPending { showsPrompt = false }
		if !showsUnlockSheet && !showsPrompt { askedAt = nil }
		if showsUnlockSheet || showsPrompt {
			if !windowPresenting, let askedAt, now - askedAt >= Self.retryAfter {
				// Asked for, and nothing came up: asked for again.
				showsUnlockSheet = false
				showsPrompt = false
				self.askedAt = nil
			}
			return
		}
		guard !windowPresenting, !gateUp else { return }
		if unlockPending {
			showsUnlockSheet = true
		} else if promptPending {
			showsPrompt = true
		} else {
			return
		}
		askedAt = now
	}
}
