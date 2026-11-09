//
//  TelemetryRequestTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
@testable import Meshtastic
import MeshtasticProtobufs
import Testing

@Suite("Telemetry requests")
struct TelemetryRequestTests {

	private let start = Date(timeIntervalSince1970: 1_000)

	@Test func eachKindRequestsItsOwnVariant() {
		#expect(TelemetryRequestKind.device.telemetry.variant == .deviceMetrics(DeviceMetrics()))
		#expect(TelemetryRequestKind.environment.telemetry.variant == .environmentMetrics(EnvironmentMetrics()))
		#expect(TelemetryRequestKind.airQuality.telemetry.variant == .airQualityMetrics(AirQualityMetrics()))
		#expect(TelemetryRequestKind.power.telemetry.variant == .powerMetrics(MeshtasticProtobufs.PowerMetrics()))
		#expect(TelemetryRequestKind.localStats.telemetry.variant == .localStats(LocalStats()))
		#expect(TelemetryRequestKind.host.telemetry.variant == .hostMetrics(HostMetrics()))
	}

	@Test func localStatsKeepsItsCooldownKey() {
		#expect(TelemetryRequestKind.localStats.rateLimitKey == "localstats")
		#expect(Set(TelemetryRequestKind.allCases.map(\.rateLimitKey)).count == TelemetryRequestKind.allCases.count)
	}

	@Test func routingErrorFailsTheRequestItAnswers() throws {
		var log = TelemetryRequestLog()
		log.sent(id: 42, kind: .environment, nodeName: "Hilltop", at: start)
		let result = log.routing(requestID: 42, error: .noResponse, at: start.addingTimeInterval(20))
		let failure = try #require(result)
		#expect(failure.kind == .environment)
		#expect(failure.nodeName == "Hilltop")
		#expect(failure.reason == RoutingError.noResponse.display)
		let repeated = log.routing(requestID: 42, error: .noResponse, at: start.addingTimeInterval(21))
		#expect(repeated == nil)
	}

	@Test func acknowledgementKeepsWaitingForTheReply() {
		var log = TelemetryRequestLog()
		log.sent(id: 7, kind: .device, nodeName: "Base", at: start)
		let ack = log.routing(requestID: 7, error: .none, at: start.addingTimeInterval(2))
		#expect(ack == nil)
		let failure = log.routing(requestID: 7, error: .maxRetransmit, at: start.addingTimeInterval(30))
		#expect(failure != nil)
	}

	@Test func replyEndsTheRequest() {
		var log = TelemetryRequestLog()
		log.sent(id: 9, kind: .power, nodeName: "Solar", at: start)
		log.replied(requestID: 9)
		let failure = log.routing(requestID: 9, error: .noResponse, at: start.addingTimeInterval(5))
		#expect(failure == nil)
	}

	@Test func otherPacketsAndOldRequestsAreIgnored() {
		var log = TelemetryRequestLog()
		log.sent(id: 1, kind: .airQuality, nodeName: "Garden", at: start)
		let otherPacket = log.routing(requestID: 2, error: .noRoute, at: start.addingTimeInterval(5))
		#expect(otherPacket == nil)
		let tooLate = log.routing(requestID: 1, error: .noRoute, at: start.addingTimeInterval(TelemetryRequestLog.window + 1))
		#expect(tooLate == nil)
		#expect(log.requests.isEmpty)
	}
}
