//
//  AdminRequestTrackerTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

@Suite("AdminRequestTracker", .serialized)
struct AdminRequestTrackerTests {

	private let connected: UInt32 = 0x1111
	private let remote: UInt32 = 0x2222
	private let other: UInt32 = 0x3333

	private func request(id: UInt32, to: UInt32, wantResponse: Bool = true) -> MeshPacket {
		var packet = MeshPacket()
		packet.id = id
		packet.from = connected
		packet.to = to
		packet.decoded.portnum = .adminApp
		packet.decoded.wantResponse = wantResponse
		return packet
	}

	private func response(requestID: UInt32, from: UInt32, pki: Bool = true) -> MeshPacket {
		var packet = MeshPacket()
		packet.id = 0xBEEF
		packet.from = from
		packet.to = connected
		packet.pkiEncrypted = pki
		packet.decoded.portnum = .adminApp
		packet.decoded.requestID = requestID
		return packet
	}

	@Test("accepts a PKI response to a request sent to that node, once")
	func acceptsMatchingResponseOnce() {
		AdminRequestTracker.recordIfAdminRequest(request(id: 10, to: remote))
		#expect(AdminRequestTracker.consumeResponse(response(requestID: 10, from: remote), connectedNodeNum: Int64(connected)))
		#expect(!AdminRequestTracker.consumeResponse(response(requestID: 10, from: remote), connectedNodeNum: Int64(connected)))
	}

	@Test("drops an unsolicited response")
	func dropsUnsolicited() {
		#expect(!AdminRequestTracker.consumeResponse(response(requestID: 0, from: remote), connectedNodeNum: Int64(connected)))
		#expect(!AdminRequestTracker.consumeResponse(response(requestID: 11, from: remote), connectedNodeNum: Int64(connected)))
	}

	@Test("drops a response from a node the request was not sent to")
	func dropsWrongSender() {
		AdminRequestTracker.recordIfAdminRequest(request(id: 12, to: remote))
		#expect(!AdminRequestTracker.consumeResponse(response(requestID: 12, from: other), connectedNodeNum: Int64(connected)))
		// The real reply still gets through afterwards.
		#expect(AdminRequestTracker.consumeResponse(response(requestID: 12, from: remote), connectedNodeNum: Int64(connected)))
	}

	@Test("drops a remote response that was not PKI encrypted")
	func dropsRemoteWithoutPKI() {
		AdminRequestTracker.recordIfAdminRequest(request(id: 13, to: remote))
		#expect(!AdminRequestTracker.consumeResponse(response(requestID: 13, from: remote, pki: false), connectedNodeNum: Int64(connected)))
	}

	@Test("accepts the connected radio's own response without PKI")
	func acceptsLocalWithoutPKI() {
		AdminRequestTracker.recordIfAdminRequest(request(id: 14, to: connected))
		#expect(AdminRequestTracker.consumeResponse(response(requestID: 14, from: connected, pki: false), connectedNodeNum: Int64(connected)))
	}

	@Test("ignores admin messages that do not ask for a reply")
	func ignoresNoResponseWanted() {
		AdminRequestTracker.recordIfAdminRequest(request(id: 15, to: remote, wantResponse: false))
		#expect(!AdminRequestTracker.consumeResponse(response(requestID: 15, from: remote), connectedNodeNum: Int64(connected)))
	}

	@Test("drops a response after the request has expired")
	func dropsExpired() {
		let sent = Date(timeIntervalSince1970: 1_000_000)
		AdminRequestTracker.recordIfAdminRequest(request(id: 16, to: remote), now: sent)
		let late = sent.addingTimeInterval(AdminRequestTracker.lifetime + 1)
		#expect(!AdminRequestTracker.consumeResponse(response(requestID: 16, from: remote), connectedNodeNum: Int64(connected), now: late))
	}
}
