//
//  MessageBottomScrollTests.swift
//  MeshtasticTests
//
//  Pins the iOS 17 decision to follow the bottom of a message list. The list
//  views pass these functions the sample taken before the fetch. The legacy
//  flag is explicit so the cases run on an iOS 18 host.
//

import CoreGraphics
import Testing

@testable import Meshtastic

@Suite("iOS 17 message scroll follow")
struct MessageBottomScrollTests {

	private func tracker(markerY: CGFloat, viewportHeight: CGFloat) -> MessageScrollTracker {
		let tracker = MessageScrollTracker()
		tracker.bottomMarkerY = markerY
		tracker.viewportHeight = viewportHeight
		return tracker
	}

	@Test func anUnmeasuredMarkerIsNotNearTheBottom() {
		#expect(!MessageScrollTracker().isNearBottom)
	}

	@Test func aMarkerInsideTheSlackIsNearTheBottom() {
		#expect(tracker(markerY: 820, viewportHeight: 800).isNearBottom)
	}

	@Test func theSlackBoundaryStillCountsAsNearTheBottom() {
		#expect(tracker(markerY: 824, viewportHeight: 800).isNearBottom)
	}

	@Test func aMarkerPastTheSlackIsNotNearTheBottom() {
		#expect(!tracker(markerY: 825, viewportHeight: 800).isNearBottom)
	}

	@Test func aMarkerThatLeftTheScreenIsNotNearTheBottom() {
		#expect(!tracker(markerY: .infinity, viewportHeight: 800).isNearBottom)
	}

	@Test func aReloadFollowsANewLastMessageWhenTheReaderWasAlreadyAtTheBottom() {
		#expect(MessageScrollTracker.shouldFollowReload(
			legacyScroll: true,
			nearBottomBeforeFetch: true,
			previousLastID: 1,
			newLastID: 2
		))
	}

	@Test func aReloadFollowsTheFirstMessageWhenTheReaderWasAlreadyAtTheBottom() {
		#expect(MessageScrollTracker.shouldFollowReload(
			legacyScroll: true,
			nearBottomBeforeFetch: true,
			previousLastID: nil,
			newLastID: 1
		))
	}

	@Test func aReloadLeavesTheReaderInOlderHistory() {
		#expect(!MessageScrollTracker.shouldFollowReload(
			legacyScroll: true,
			nearBottomBeforeFetch: false,
			previousLastID: 1,
			newLastID: 2
		))
	}

	@Test func aReloadDoesNotFollowWhenTheLastMessageStaysTheSame() {
		#expect(!MessageScrollTracker.shouldFollowReload(
			legacyScroll: true,
			nearBottomBeforeFetch: true,
			previousLastID: 7,
			newLastID: 7
		))
	}

	@Test func aReloadOnTheModernPathDoesNotScrollTheListItself() {
		#expect(!MessageScrollTracker.shouldFollowReload(
			legacyScroll: false,
			nearBottomBeforeFetch: true,
			previousLastID: 1,
			newLastID: 2
		))
	}

	@Test func aSendFollowsWhenTheReloadDidNot() {
		// Reader was in older history, or the last id did not change.
		#expect(MessageScrollTracker.shouldFollowSend(
			legacyScroll: true,
			scrollRequestChangedDuringLoad: false
		))
	}

	@Test func aSendDoesNotRequestASecondScrollWhenTheReloadAlreadyFollowed() {
		#expect(!MessageScrollTracker.shouldFollowSend(
			legacyScroll: true,
			scrollRequestChangedDuringLoad: true
		))
	}

	@Test func aSendFollowsOnTheModernPathWhetherOrNotTheReloadScrolled() {
		#expect(MessageScrollTracker.shouldFollowSend(
			legacyScroll: false,
			scrollRequestChangedDuringLoad: false
		))
		#expect(MessageScrollTracker.shouldFollowSend(
			legacyScroll: false,
			scrollRequestChangedDuringLoad: true
		))
	}
}
