//
//  TraceRouteStateTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import Foundation
import Testing
@testable import Meshtastic

@Suite("Trace route state")
struct TraceRouteStateTests {

	private let sentTime = Date(timeIntervalSince1970: 1_800_000_000)

	private func route(sent: Bool, response: Bool, rateLimited: Bool = false, hopsTowards: Int32 = 2) -> TraceRouteEntity {
		let route = TraceRouteEntity()
		route.sent = sent
		route.response = response
		route.rateLimited = rateLimited
		route.hopsTowards = hopsTowards
		route.time = sentTime
		return route
	}

	@Test("A sent request is pending inside the wait window")
	func pending() {
		let request = route(sent: true, response: false)
		#expect(request.state(now: sentTime.addingTimeInterval(30)) == .pending)
		#expect(request.state(now: sentTime.addingTimeInterval(119)) == .pending)
	}

	@Test("A sent request with nothing back after the window has no response")
	func noResponse() {
		let request = route(sent: true, response: false)
		#expect(request.state(now: sentTime.addingTimeInterval(120)) == .noResponse)
		#expect(request.state(now: sentTime.addingTimeInterval(3600)) == .noResponse)
	}

	@Test("A sent request without a time has no response")
	func noTime() {
		let request = route(sent: true, response: false)
		request.time = nil
		#expect(request.state(now: sentTime) == .noResponse)
	}

	@Test("A rate-limited request stays rate limited")
	func rateLimited() {
		let request = route(sent: true, response: false, rateLimited: true)
		#expect(request.state(now: sentTime.addingTimeInterval(1)) == .rateLimited)
		#expect(request.state(now: sentTime.addingTimeInterval(3600)) == .rateLimited)
	}

	@Test("An older unsent record without a response reads as rate limited")
	func legacyRateLimited() {
		let request = route(sent: false, response: false)
		#expect(request.state(now: sentTime) == .rateLimited)
	}

	@Test("Responses are complete when ours and observed otherwise")
	func responded() {
		#expect(route(sent: true, response: true).state(now: sentTime) == .complete)
		#expect(route(sent: false, response: true).state(now: sentTime) == .observed)
	}

	@Test("Only waiting, no response and rate limited have a label")
	func labels() {
		#expect(TraceRouteState.pending.label != nil)
		#expect(TraceRouteState.noResponse.label != nil)
		#expect(TraceRouteState.rateLimited.label != nil)
		#expect(TraceRouteState.complete.label == nil)
		#expect(TraceRouteState.observed.label == nil)
	}

	@Test("Direct routes get the two-person icon, others the state icon")
	func rowIcons() {
		#expect(route(sent: true, response: true, hopsTowards: 0).rowSystemImage(now: sentTime) == "person.line.dotted.person")
		#expect(route(sent: true, response: true, hopsTowards: 3).rowSystemImage(now: sentTime) == "point.3.connected.trianglepath.dotted")
		#expect(route(sent: true, response: false, hopsTowards: 0).rowSystemImage(now: sentTime) == "hourglass")
		#expect(route(sent: true, response: false, rateLimited: true).rowSystemImage(now: sentTime) == TraceRouteState.rateLimited.systemImage)
	}
}
