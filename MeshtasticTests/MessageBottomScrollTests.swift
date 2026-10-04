//
//  MessageBottomScrollTests.swift
//  MeshtasticTests
//
//  Pins the decision to follow the bottom of a message list. The list views
//  pass these functions the sample taken before the fetch.
//

import CoreGraphics
import Testing

@testable import Meshtastic

@Suite("Message scroll follow")
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

	@Test func theScrollGeometryWinsOverTheMarkerOnceItIsSet() {
		let t = tracker(markerY: .infinity, viewportHeight: 800)
		t.scrolledToBottom = true
		#expect(t.isNearBottom)
		t.scrolledToBottom = false
		#expect(!t.isNearBottom)
	}

	@Test func aReloadFollowsANewLastMessageWhenTheReaderWasAlreadyAtTheBottom() {
		#expect(MessageScrollTracker.shouldFollowReload(nearBottomBeforeFetch: true, previousLastID: 1, newLastID: 2))
	}

	@Test func aReloadFollowsTheFirstMessageWhenTheReaderWasAlreadyAtTheBottom() {
		#expect(MessageScrollTracker.shouldFollowReload(nearBottomBeforeFetch: true, previousLastID: nil, newLastID: 1))
	}

	@Test func aReloadLeavesTheReaderInOlderHistory() {
		#expect(!MessageScrollTracker.shouldFollowReload(nearBottomBeforeFetch: false, previousLastID: 1, newLastID: 2))
	}

	@Test func aReloadDoesNotFollowWhenTheLastMessageStaysTheSame() {
		#expect(!MessageScrollTracker.shouldFollowReload(nearBottomBeforeFetch: true, previousLastID: 7, newLastID: 7))
	}

	@Test func aSendFollowsWhenTheReloadDidNot() {
		#expect(MessageScrollTracker.shouldFollowSend(scrollRequestChangedDuringLoad: false))
	}

	@Test func aSendDoesNotRequestASecondScrollWhenTheReloadAlreadyFollowed() {
		#expect(!MessageScrollTracker.shouldFollowSend(scrollRequestChangedDuringLoad: true))
	}
}
