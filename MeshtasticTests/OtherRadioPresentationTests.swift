//
//  OtherRadioPresentationTests.swift
//  MeshtasticTests
//
//  Feature 021, review V14 P3: another radio's passphrase sheet and prompt in the one window.
//

import Foundation
import Testing
@testable import Meshtastic

@Suite("Another radio's passphrase sheet and prompt")
struct OtherRadioPresentationTests {

	private let start = ContinuousClock.now

	private func at(_ seconds: Double) -> ContinuousClock.Instant {
		start.advanced(by: .milliseconds(Int(seconds * 1000)))
	}

	@Test("Asked for only when the window presents nothing and none of its own gates is up")
	func waitsForAFreeWindow() {
		var turn = OtherRadioPresentation()
		turn.update(unlockPending: false, promptPending: true, windowPresenting: true, gateUp: false, now: at(0))
		#expect(!turn.showsPrompt, "a sheet the app opened is up")
		turn.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: true, now: at(0.5))
		#expect(!turn.showsPrompt, "a gate or the Choose Radios sheet is up")
		turn.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: false, now: at(1))
		#expect(turn.showsPrompt)
	}

	@Test("One at a time, the passphrase sheet first")
	func oneAtATime() {
		var turn = OtherRadioPresentation()
		turn.update(unlockPending: true, promptPending: true, windowPresenting: false, gateUp: false, now: at(0))
		#expect(turn.showsUnlockSheet)
		#expect(!turn.showsPrompt)
		// The sheet is up; the prompt waits.
		turn.update(unlockPending: true, promptPending: true, windowPresenting: true, gateUp: false, now: at(5))
		#expect(turn.showsUnlockSheet)
		#expect(!turn.showsPrompt)
		// The sheet closed; the window is free again: the prompt's turn.
		turn.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: false, now: at(6))
		#expect(!turn.showsUnlockSheet)
		#expect(turn.showsPrompt)
	}

	@Test("Kept while it's up; asked for again when nothing came up")
	func askedAgainWhenLost() {
		var turn = OtherRadioPresentation()
		turn.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: false, now: at(0))
		#expect(turn.showsPrompt)
		// Up: kept, however long.
		turn.update(unlockPending: false, promptPending: true, windowPresenting: true, gateUp: false, now: at(30))
		#expect(turn.showsPrompt)

		var lost = OtherRadioPresentation()
		lost.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: false, now: at(0))
		// Nothing came up: not before two seconds, then let go ...
		lost.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: false, now: at(1))
		#expect(lost.showsPrompt)
		lost.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: false, now: at(2))
		#expect(!lost.showsPrompt)
		// ... and asked for again.
		lost.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: false, now: at(2.5))
		#expect(lost.showsPrompt)
	}

	@Test("Answered or no longer needed, it's no longer asked for")
	func resolved() {
		var turn = OtherRadioPresentation()
		turn.update(unlockPending: false, promptPending: true, windowPresenting: false, gateUp: false, now: at(0))
		turn.update(unlockPending: false, promptPending: false, windowPresenting: true, gateUp: false, now: at(1))
		#expect(!turn.showsPrompt)
		#expect(turn == OtherRadioPresentation())
	}
}
