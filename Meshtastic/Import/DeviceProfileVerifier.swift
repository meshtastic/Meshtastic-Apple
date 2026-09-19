//
//  DeviceProfileVerifier.swift
//  Meshtastic
//
//  Checks, after the fact, whether an imported device profile actually landed on the radio.
//
//  This exists because the firmware acks writes it silently discards. On a Heltec V4, an unpaced burst
//  of 8 module-config writes had only 5 processed on firmware 2.7.27 and 7 on 2.8.0, with no
//  client-visible error either time. Pacing and the edit transaction reduce that (see
//  DeviceProfileImporter), but nothing the client can observe during a run proves a write landed. Only
//  reading the config back afterwards does.
//

import Foundation
import MeshtasticProtobufs
import SwiftProtobuf

// MARK: - Source seam

/// Supplies the radio's current config as the app last received it. Production reads the connected
/// node's SwiftData entities; tests use a mock.
@MainActor
protocol ProfileConfigSource {
	/// The current payload for a kind, or nil when the kind has no readable counterpart.
	func currentPayload(for kind: ImportItemKind) -> ImportPayload?
	/// When the app last completed a config download from the radio.
	///
	/// Verification is meaningless against a stale cache: if this predates the import, the entities
	/// still hold pre-import values and every item would look dropped. `verify` refuses to run in that
	/// case rather than report a false wipe.
	var lastConfigRefresh: Date? { get }
}

// MARK: - Result

/// What verification concluded for one item.
enum VerificationOutcome: Equatable {
	/// Every field the profile set to a non-default value is present on the radio.
	case applied
	/// No field the profile set landed, and the radio still holds its pre-import values. This is the
	/// signature of a whole admin message being dropped, which is the observed failure.
	case likelyDropped
	/// Some fields landed and some did not, or the radio reports values matching neither. Firmware
	/// normalizes some inputs (setting neighbor_info.update_interval to 0 reads back as its default
	/// 21600), so a difference is not proof of failure.
	case inconclusive(detail: String)
	/// Nothing to compare: either the kind has no readable counterpart (channel URL, ringtone, canned
	/// message text) or the profile set only default values, which carry no signal.
	case notComparable(reason: String)
}

/// Determines whether a post-import readback can be verified exactly once.
///
/// `refreshNotBefore` is recorded before the import begins. This lets a config refresh that arrives
/// while the import is still sending count as a readback, without accepting the cache from before it.
struct DeviceProfileVerificationReadiness: Equatable {
	let expectsReconnect: Bool
	let refreshNotBefore: Date?
	let lastConfigRefresh: Date?
	let hasVerification: Bool

	var shouldVerify: Bool {
		guard expectsReconnect, !hasVerification,
			  let refreshNotBefore, let lastConfigRefresh
		else { return false }
		return lastConfigRefresh >= refreshNotBefore
	}
}

struct DeviceProfileVerification: Equatable {
	var outcomes: [(kind: ImportItemKind, outcome: VerificationOutcome)] = []
	/// Set when verification could not run at all, with the reason.
	var unavailable: String?

	var applied: [ImportItemKind] { outcomes.filter { $0.outcome == .applied }.map(\.kind) }
	var likelyDropped: [ImportItemKind] { outcomes.filter { $0.outcome == .likelyDropped }.map(\.kind) }
	var inconclusive: [ImportItemKind] {
		outcomes.filter { if case .inconclusive = $0.outcome { return true } else { return false } }.map(\.kind)
	}
	var notComparable: [ImportItemKind] {
		outcomes.filter { if case .notComparable = $0.outcome { return true } else { return false } }.map(\.kind)
	}
	/// True when nothing looks lost. Inconclusive items are not failures.
	var isClean: Bool { unavailable == nil && likelyDropped.isEmpty }

	static func == (lhs: DeviceProfileVerification, rhs: DeviceProfileVerification) -> Bool {
		lhs.unavailable == rhs.unavailable
			&& lhs.outcomes.count == rhs.outcomes.count
			&& zip(lhs.outcomes, rhs.outcomes).allSatisfy { $0.kind == $1.kind && $0.outcome == $1.outcome }
	}
}

// MARK: - Verifier

enum DeviceProfileVerifier {

	/// Compares what the import sent against what the radio reports now.
	///
	/// Comparison is per-field and restricted to fields the profile set to a NON-DEFAULT value. Whole
	/// message equality does not work here for two reasons:
	///
	///  1. Firmware normalizes. Sending `neighbor_info.update_interval = 0` reads back as 21600.
	///     Because `before` is frequently already at the default, a message-level rule of
	///     "after == before means dropped" would flag that correctly-applied write as a failure.
	///  2. `after` is rebuilt from SwiftData entities, so it can differ from the sent message in
	///     presence bits and materialized fields even when the values agree.
	///
	/// proto3 default-valued scalars are indistinguishable from unset, and they are the prime
	/// normalization targets, so they carry no verification signal in either direction and are
	/// excluded. SwiftProtobuf's JSON encoding omits them, which gives that projection for free.
	@MainActor
	static func verify(
		applied kinds: [ImportItemKind],
		plan: DeviceProfileImportPlan,
		before: [ImportItemKind: ImportPayload],
		source: ProfileConfigSource,
		readbackNotBefore: Date
	) -> DeviceProfileVerification {
		var report = DeviceProfileVerification()

		// A readback older than the import proves nothing: the entities still hold pre-import values,
		// which would read as a total wipe. Refuse rather than report a false failure.
		guard let refreshed = source.lastConfigRefresh else {
			report.unavailable = "The app has not received a configuration from the radio yet."
			return report
		}
		guard refreshed >= readbackNotBefore else {
			report.unavailable = "The radio has not sent its configuration since the import began."
			return report
		}

		let sentByKind = Dictionary(
			plan.items.map { ($0.kind, $0.payload) }, uniquingKeysWith: { first, _ in first }
		)

		for kind in kinds {
			guard let sent = sentByKind[kind] else { continue }
			report.outcomes.append((kind, outcome(kind: kind, sent: sent,
												 before: before[kind], source: source)))
		}
		return report
	}

	@MainActor
	private static func outcome(
		kind: ImportItemKind,
		sent: ImportPayload,
		before: ImportPayload?,
		source: ProfileConfigSource
	) -> VerificationOutcome {
		guard let sentMessage = sent.message else {
			return .notComparable(reason: "This setting cannot be read back from the radio.")
		}
		guard let actual = source.currentPayload(for: kind), let actualMessage = actual.message else {
			return .notComparable(reason: "The app has no stored value for this setting.")
		}

		let sentFields = nonDefaultFields(sentMessage)
		guard !sentFields.isEmpty else {
			return .notComparable(reason: "The profile set only default values, which cannot be verified.")
		}
		let actualFields = nonDefaultFields(actualMessage)
		let beforeFields = before?.message.map(nonDefaultFields) ?? [:]

		var landed: [String] = []
		var missing: [String] = []
		var unchangedFromBefore = 0
		for (field, sentValue) in sentFields {
			let actualValue = actualFields[field]
			if actualValue == sentValue {
				landed.append(field)
			} else {
				missing.append(field)
				if actualValue == beforeFields[field] { unchangedFromBefore += 1 }
			}
		}

		if missing.isEmpty { return .applied }
		// Nothing landed and the radio still reports exactly what it had before: the whole message
		// almost certainly never arrived.
		if landed.isEmpty && unchangedFromBefore == missing.count {
			return .likelyDropped
		}
		let sample = missing.sorted().prefix(3).joined(separator: ", ")
		return .inconclusive(detail: "\(landed.count) of \(sentFields.count) settings match; "
							 + "differing: \(sample)\(missing.count > 3 ? "…" : "")")
	}

	/// The message's fields that carry a non-default value, as JSON name to rendered value.
	///
	/// SwiftProtobuf omits proto3 default-valued fields from JSON unless explicitly asked, so this is
	/// exactly the projection we want and it works for every message type without reflection.
	private static func nonDefaultFields(_ message: any SwiftProtobuf.Message) -> [String: String] {
		guard let data = try? message.jsonUTF8Data(),
			  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return [:]
		}
		return object.mapValues { String(describing: $0) }
	}
}

// MARK: - Production source

/// Reads the connected node's config back out of SwiftData, using the same `protoConfig` accessors the
/// export path uses, so verification compares like with like.
@MainActor
struct NodeProfileConfigSource: ProfileConfigSource {
	let node: NodeInfoEntity
	let lastConfigRefresh: Date?

	// swiftlint:disable:next cyclomatic_complexity
	func currentPayload(for kind: ImportItemKind) -> ImportPayload? {
		switch kind {
		case .owner: return node.user.map { ImportPayload.owner($0.toProto()) }
		case .deviceConfig: return node.deviceConfig.map { .deviceConfig($0.protoConfig) }
		case .displayConfig: return node.displayConfig.map { .displayConfig($0.protoConfig) }
		case .positionConfig: return node.positionConfig.map { .positionConfig($0.protoConfig) }
		case .powerConfig: return node.powerConfig.map { .powerConfig($0.protoConfig) }
		case .networkConfig: return node.networkConfig.map { .networkConfig($0.protoConfig) }
		case .bluetoothConfig: return node.bluetoothConfig.map { .bluetoothConfig($0.protoConfig) }
		case .securityConfig: return node.securityConfig.map { .securityConfig($0.protoConfig) }
		case .loraConfig: return node.loRaConfig.map { .loraConfig($0.protoConfig) }
		case .mqtt: return node.mqttConfig.map { .mqtt($0.protoConfig) }
		case .serial: return node.serialConfig.map { .serial($0.protoConfig) }
		case .externalNotification:
			return node.externalNotificationConfig.map { .externalNotification($0.protoConfig) }
		case .storeForward: return node.storeForwardConfig.map { .storeForward($0.protoConfig) }
		case .rangeTest: return node.rangeTestConfig.map { .rangeTest($0.protoConfig) }
		case .telemetry: return node.telemetryConfig.map { .telemetry($0.protoConfig) }
		case .cannedMessage: return node.cannedMessageConfig.map { .cannedMessage($0.protoConfig) }
		case .audio: return node.audioConfig.map { .audio($0.protoConfig) }
		case .neighborInfo: return node.neighborInfoConfig.map { .neighborInfo($0.protoConfig) }
		case .ambientLighting: return node.ambientLightingConfig.map { .ambientLighting($0.protoConfig) }
		case .detectionSensor: return node.detectionSensorConfig.map { .detectionSensor($0.protoConfig) }
		case .paxcounter: return node.paxCounterConfig.map { .paxcounter($0.protoConfig) }
		case .tak: return node.takConfig.map { .tak($0.protoConfig) }
		case .trafficManagement:
			return node.trafficManagementConfig.map { .trafficManagement($0.protoConfig) }
		case .statusMessage: return node.statusMessageConfig.map { .statusMessage($0.protoConfig) }
		// The radio never echoes these back in a comparable form.
		case .ringtone, .cannedMessagesText, .channelURL, .fixedPosition: return nil
		}
	}
}

// MARK: - Payload bridging

extension ImportPayload {
	/// The underlying protobuf message, when this payload carries one.
	///
	/// The string-shaped payloads have no message form, and the channel URL is a packed representation
	/// the radio never echoes back, so none of them can be verified.
	var message: (any SwiftProtobuf.Message)? {
		switch self {
		case .owner(let value): return value
		case .deviceConfig(let value): return value
		case .displayConfig(let value): return value
		case .positionConfig(let value): return value
		case .powerConfig(let value): return value
		case .networkConfig(let value): return value
		case .bluetoothConfig(let value): return value
		case .securityConfig(let value): return value
		case .mqtt(let value): return value
		case .serial(let value): return value
		case .externalNotification(let value): return value
		case .storeForward(let value): return value
		case .rangeTest(let value): return value
		case .telemetry(let value): return value
		case .cannedMessage(let value): return value
		case .audio(let value): return value
		case .neighborInfo(let value): return value
		case .ambientLighting(let value): return value
		case .detectionSensor(let value): return value
		case .paxcounter(let value): return value
		case .tak(let value): return value
		case .trafficManagement(let value): return value
		case .statusMessage(let value): return value
		case .loraConfig(let value): return value
		case .fixedPosition(let value): return value
		case .ringtone, .cannedMessagesText, .channelURL: return nil
		}
	}
}
