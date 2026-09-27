//
//  ScriptedRadio.swift
//  MeshtasticTests
//
//  A radio for tests that answers the two want-config requests the way firmware does (feature
//  021, T068). Used by the connect-flow tests and by the tests that connect several radios.
//

import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - Scripted radio

/// A radio that answers the two want-config requests the way firmware does: config, then
/// `configCompleteID`; node DB, then `configCompleteID`. Records everything the app sends.
actor ScriptedRadio: Connection {
	let type: TransportType = .tcp
	var isConnected = true
	private(set) var sent: [ToRadio] = []
	private(set) var disconnects = 0
	private var continuation: AsyncStream<ConnectionEvent>.Continuation?

	let nodeNum: UInt32
	let firmwareVersion: String
	let dumpNodes: [UInt32]
	/// When false, the radio never finishes the config request.
	let answersConfig: Bool
	/// The device config's `tzdef`; blank asks the app to fill it in.
	let timezone: String
	/// Canned messages module on, which makes the app ask for the messages.
	let cannedMessages: Bool
	/// Sent after the config request completes, as lock-down firmware sends its status.
	let afterConfig: [FromRadio.OneOf_PayloadVariant]

	init(
		nodeNum: UInt32,
		firmwareVersion: String = "2.7.15.567b8ea",
		dumpNodes: [UInt32] = [],
		answersConfig: Bool = true,
		timezone: String = "UTC0",
		cannedMessages: Bool = false,
		afterConfig: [FromRadio.OneOf_PayloadVariant] = []
	) {
		self.nodeNum = nodeNum
		self.firmwareVersion = firmwareVersion
		self.dumpNodes = dumpNodes
		self.answersConfig = answersConfig
		self.timezone = timezone
		self.cannedMessages = cannedMessages
		self.afterConfig = afterConfig
	}

	/// Sends an event as if the link produced it.
	func emit(_ event: ConnectionEvent) {
		continuation?.yield(event)
	}

	func emit(_ variant: FromRadio.OneOf_PayloadVariant) {
		yield(variant)
	}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		let (stream, continuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
		self.continuation = continuation
		return stream
	}

	func send(_ data: ToRadio) async throws {
		guard isConnected else { throw AccessoryError.connectionFailed("Scripted radio disconnected") }
		sent.append(data)
		if case .wantConfigID(let nonce) = data.payloadVariant {
			// After a round trip, like a real radio. Answering inside `send` beats the app's
			// first-node wait for an empty node DB (see HANDOFF.md › Gotchas, T068).
			Task {
				try? await Task.sleep(for: .milliseconds(20))
				self.answer(nonce)
			}
		}
	}

	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {
		isConnected = false
		disconnects += 1
		continuation?.finish()
	}

	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}

	private func yield(_ variant: FromRadio.OneOf_PayloadVariant) {
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = variant
		continuation?.yield(.data(fromRadio))
	}

	private func answer(_ nonce: UInt32) {
		switch nonce {
		case 69420:
			guard answersConfig else { return }
			var myInfo = MyNodeInfo()
			myInfo.myNodeNum = nodeNum
			// Unique per radio: the app treats a matching device id as the same radio renumbered.
			myInfo.deviceID = withUnsafeBytes(of: nodeNum.bigEndian) { Data($0) } + Data(repeating: 0xD0, count: 12)
			myInfo.nodedbCount = UInt32(dumpNodes.count + 1)
			yield(.myInfo(myInfo))

			var metadata = DeviceMetadata()
			metadata.firmwareVersion = firmwareVersion
			yield(.metadata(metadata))

			yield(.nodeInfo(Self.node(nodeNum, name: "Scripted Radio", short: "SCR")))

			for index in 0..<8 {
				var channel = Channel()
				channel.index = Int32(index)
				if index == 0 {
					channel.role = .primary
					var settings = ChannelSettings()
					settings.psk = Data([1])
					channel.settings = settings
				} else {
					channel.role = .disabled
				}
				yield(.channel(channel))
			}

			var device = Config.DeviceConfig()
			// A blank timezone makes the app send one; a set one keeps the admin traffic quiet.
			device.tzdef = timezone
			var config = Config()
			config.payloadVariant = .device(device)
			yield(.config(config))

			if cannedMessages {
				var canned = ModuleConfig.CannedMessageConfig()
				canned.enabled = true
				var moduleConfig = ModuleConfig()
				moduleConfig.payloadVariant = .cannedMessage(canned)
				yield(.moduleConfig(moduleConfig))
			}

			yield(.configCompleteID(nonce))
			for variant in afterConfig {
				yield(variant)
			}

		case 69421:
			for num in dumpNodes {
				yield(.nodeInfo(Self.node(num, name: "Node \(num)", short: "N\(num % 100)")))
			}
			yield(.configCompleteID(nonce))

		default:
			break
		}
	}

	static func node(_ num: UInt32, name: String, short: String) -> NodeInfo {
		var user = User()
		user.id = "!" + String(format: "%08x", num)
		user.longName = name
		user.shortName = short
		user.hwModel = .tbeam
		var node = NodeInfo()
		node.num = num
		node.user = user
		node.lastHeard = UInt32(Date().timeIntervalSince1970)
		return node
	}
}

/// A TCP transport that hands out the scripted radio, or fails the way it's told to.
final class ScriptedTransport: Transport, @unchecked Sendable {
	let type: TransportType = .tcp
	var status: TransportStatus { .ready }
	let supportsManualConnection = false

	let requiresPeriodicHeartbeat: Bool
	private let radio: ScriptedRadio
	/// Radios for particular devices, by `Device.identifier`; others get `radio`.
	private let radiosByIdentifier: [String: ScriptedRadio]
	private let failure: Error?
	private let lock = NSLock()
	private var attempts = 0

	init(radio: ScriptedRadio, failure: Error? = nil, requiresPeriodicHeartbeat: Bool = false, radiosByIdentifier: [String: ScriptedRadio] = [:]) {
		self.radio = radio
		self.failure = failure
		self.requiresPeriodicHeartbeat = requiresPeriodicHeartbeat
		self.radiosByIdentifier = radiosByIdentifier
	}

	var connectAttempts: Int { lock.withLock { attempts } }

	func discoverDevices() async -> AsyncStream<DiscoveryEvent> { AsyncStream { $0.finish() } }
	func connect(to device: Device) async throws -> any Connection {
		lock.withLock { attempts += 1 }
		if let failure { throw failure }
		return radiosByIdentifier[device.identifier] ?? radio
	}
	func device(forManualConnection: String) -> Device? { nil }
	func manuallyConnect(toDevice: Device) async throws {}
}

/// What the app sent, in a form the tests can compare.
enum SentItem: Equatable {
	case heartbeat
	case wantConfig(UInt32)
	case setTime
	case setTimezone(String)
	case cannedMessagesRequest
	case admin
	case packet
	case other
}

func describe(_ toRadio: ToRadio) -> SentItem {
	switch toRadio.payloadVariant {
	case .heartbeat:
		return .heartbeat
	case .wantConfigID(let nonce):
		return .wantConfig(nonce)
	case .packet(let packet):
		guard packet.decoded.portnum == .adminApp,
			  let admin = try? AdminMessage(serializedBytes: packet.decoded.payload) else { return .packet }
		switch admin.payloadVariant {
		case .setTimeOnly:
			return .setTime
		case .setConfig(let config):
			if case .device(let device) = config.payloadVariant { return .setTimezone(device.tzdef) }
			return .admin
		case .getCannedMessageModuleMessagesRequest:
			return .cannedMessagesRequest
		default:
			return .admin
		}
	default:
		return .other
	}
}
