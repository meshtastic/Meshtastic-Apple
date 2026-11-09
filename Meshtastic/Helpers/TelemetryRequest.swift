//
//  TelemetryRequest.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
import MeshtasticProtobufs
import OSLog

/// A kind of telemetry a node can be asked for on demand. Since firmware 2.7.13 telemetry
/// broadcasts are off by default, so asking is often the only way to see a node's readings.
enum TelemetryRequestKind: String, CaseIterable, Identifiable {
	case device
	case environment
	case airQuality
	case power
	case localStats
	/// Linux meshtasticd nodes only.
	case host

	var id: String { rawValue }

	/// The readings, for use inside a sentence: "device metrics".
	var name: String {
		switch self {
		case .device: String(localized: "device metrics", comment: "Telemetry request: the kind of readings, used inside a sentence")
		case .environment: String(localized: "environment metrics", comment: "Telemetry request: the kind of readings, used inside a sentence")
		case .airQuality: String(localized: "air quality metrics", comment: "Telemetry request: the kind of readings, used inside a sentence")
		case .power: String(localized: "power metrics", comment: "Telemetry request: the kind of readings, used inside a sentence")
		case .localStats: String(localized: "local stats", comment: "Telemetry request: the kind of readings, used inside a sentence")
		case .host: String(localized: "host metrics", comment: "Telemetry request: the kind of readings, used inside a sentence")
		}
	}

	/// The request button's accessibility label.
	var requestTitle: String {
		switch self {
		case .device: String(localized: "Request Device Metrics")
		case .environment: String(localized: "Request Environment Metrics")
		case .airQuality: String(localized: "Request Air Quality Metrics")
		case .power: String(localized: "Request Power Metrics")
		case .localStats: String(localized: "Request Local Stats")
		case .host: String(localized: "Request Host Metrics")
		}
	}

	/// Local stats keeps the key its request button has always used.
	var rateLimitKey: String {
		self == .localStats ? "localstats" : "telemetry.\(rawValue)"
	}

	/// The request: a telemetry packet with this variant set and empty.
	var telemetry: Telemetry {
		var telemetry = Telemetry()
		switch self {
		case .device: telemetry.deviceMetrics = DeviceMetrics()
		case .environment: telemetry.environmentMetrics = EnvironmentMetrics()
		case .airQuality: telemetry.airQualityMetrics = AirQualityMetrics()
		case .power: telemetry.powerMetrics = MeshtasticProtobufs.PowerMetrics()
		case .localStats: telemetry.localStats = LocalStats()
		case .host: telemetry.hostMetrics = HostMetrics()
		}
		return telemetry
	}
}

/// Telemetry requests sent in the last few minutes, by packet id, so a routing error that
/// answers one can say which request failed and why.
struct TelemetryRequestLog {
	struct Request: Equatable {
		let kind: TelemetryRequestKind
		let nodeName: String
		let sentAt: Date
	}

	struct Failure: Identifiable, Equatable {
		let id = UUID()
		let kind: TelemetryRequestKind
		let nodeName: String
		let reason: String
	}

	/// Long enough for a multi-hop request to run out of retries on the slowest presets.
	static let window: TimeInterval = 5 * 60

	private(set) var requests: [UInt32: Request] = [:]

	mutating func sent(id: UInt32, kind: TelemetryRequestKind, nodeName: String, at now: Date) {
		prune(now: now)
		requests[id] = Request(kind: kind, nodeName: nodeName, sentAt: now)
	}

	/// A routing packet answering `requestID`. An error ends the request as a failure; an
	/// acknowledgement leaves it waiting for the reply.
	mutating func routing(requestID: UInt32, error: Routing.Error, at now: Date) -> Failure? {
		prune(now: now)
		guard error != .none, let request = requests.removeValue(forKey: requestID) else { return nil }
		let reason = RoutingError(rawValue: error.rawValue)?.display ?? String(localized: "Unknown")
		return Failure(kind: request.kind, nodeName: request.nodeName, reason: reason)
	}

	/// The node's reply arrived; nothing more to watch for.
	mutating func replied(requestID: UInt32) {
		requests.removeValue(forKey: requestID)
	}

	private mutating func prune(now: Date) {
		requests = requests.filter { now.timeIntervalSince($0.value.sentAt) < Self.window }
	}
}

/// Watches the mesh for routing errors that answer telemetry requests, and publishes the
/// failure for the app to show. Android's `RequestNakWatcher` does the same.
@MainActor
final class TelemetryRequestTracker: ObservableObject {
	static let shared = TelemetryRequestTracker()

	@Published var failure: TelemetryRequestLog.Failure?
	private var log = TelemetryRequestLog()

	func sent(id: UInt32, kind: TelemetryRequestKind, nodeName: String) {
		log.sent(id: id, kind: kind, nodeName: nodeName, at: .now)
	}

	/// A request that never went out.
	func forget(id: UInt32) {
		log.replied(requestID: id)
	}

	func deliverRouting(_ packet: MeshPacket) {
		guard packet.decoded.requestID != 0,
			  let routing = try? Routing(serializedBytes: packet.decoded.payload),
			  let failure = log.routing(requestID: packet.decoded.requestID, error: routing.errorReason, at: .now) else { return }
		Logger.mesh.warning("📊 Telemetry request \(packet.decoded.requestID, privacy: .public) for \(failure.kind.rawValue, privacy: .public) failed: \(failure.reason, privacy: .public)")
		self.failure = failure
	}

	func deliverReply(_ packet: MeshPacket) {
		guard packet.decoded.requestID != 0 else { return }
		log.replied(requestID: packet.decoded.requestID)
	}
}
