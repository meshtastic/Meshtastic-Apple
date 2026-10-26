//
//  CinemaReopenLatchTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/26/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Cinema reopen latch")
struct CinemaReopenLatchTests {
	private let start = Date(timeIntervalSinceReferenceDate: 1_000)
	private let timeout = CinemaScene.ReopenLatch.timeout

	@Test func theFirstAskOpensAndOneOnItsWayIsNotRepeated() {
		var latch = CinemaScene.ReopenLatch()
		#expect(!latch.awaitingWindow)
		let first = latch.request(at: start)
		let second = latch.request(at: start + 1)
		#expect(first)
		#expect(!second)
		#expect(latch.isPending(at: start + 1))
		#expect(latch.awaitingWindow)
	}

	@Test func aWindowAppearingClearsIt() {
		var latch = CinemaScene.ReopenLatch()
		_ = latch.request(at: start)
		latch.windowAppeared()
		#expect(!latch.awaitingWindow)
		#expect(!latch.isPending(at: start + 1))
		let next = latch.request(at: start + 1)
		#expect(next)
	}

	@Test func aDroppedAskExpiresSoTheNextOneGoesThrough() {
		var latch = CinemaScene.ReopenLatch()
		_ = latch.request(at: start)
		let expiry = start + timeout
		let early = latch.request(at: expiry - 0.5)
		#expect(!early)
		#expect(latch.isPending(at: expiry - 0.5))
		#expect(!latch.isPending(at: expiry))
		// Still owed a window, so the return from the background asks again.
		#expect(latch.awaitingWindow)
		let again = latch.request(at: expiry)
		#expect(again)
		#expect(latch.requestedAt == expiry)
	}

	@Test func timeRemainingCountsDownToZero() {
		var latch = CinemaScene.ReopenLatch()
		#expect(latch.timeRemaining(at: start) == 0)
		_ = latch.request(at: start)
		#expect(latch.timeRemaining(at: start + 1) == timeout - 1)
		#expect(latch.timeRemaining(at: start + timeout) == 0)
		#expect(latch.timeRemaining(at: start + timeout + 10) == 0)
	}
}
