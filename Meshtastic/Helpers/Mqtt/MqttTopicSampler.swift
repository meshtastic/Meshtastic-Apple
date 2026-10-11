//
//  MqttTopicSampler.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/11/26.
//

import CocoaMQTT
import Foundation
import MeshtasticProtobufs
import OSLog

/// A subscribe-only broker connection that listens for a fixed time and tallies the roots it hears.
/// Separate from `MqttClientProxyManager` because the proxy forwards everything it receives to the
/// radio; nothing heard here reaches the radio. Main-actor so the published state, the deadline tasks
/// and the delegate callbacks (`delegateQueue` is main) share one isolation.
@MainActor
final class MqttTopicSampler: NSObject, ObservableObject {
	enum Phase: Equatable {
		case idle, connecting, subscribing, sampling, finished, failed(String)
	}

	struct Settings: Equatable {
		var host: String
		var port: UInt16
		var useTLS: Bool
		var username: String?
		var password: String?

		/// The rules `MqttClientProxyManager.connectFromConfigSettings` applies, on the form's draft:
		/// blank address -> public server; "host:port" split; the public server -> TLS, 8883 and its
		/// fixed credentials whatever was typed; otherwise the form's TLS switch (8883/1883 unless a
		/// port was given) and its username/password, empty strings becoming nil.
		@MainActor
		init(config: ModuleConfig.MQTTConfig) {
			let address = config.address.trimmingCharacters(in: .whitespaces)
			var host = address.isEmpty ? MQTTConfig.publicServer : address
			var typedPort: UInt16?
			if let colon = host.firstIndex(of: ":") {
				typedPort = UInt16(host[host.index(after: colon)...])
				host = String(host[..<colon])
			}
			self.host = host
			if MQTTConfig.usesPublicServer(host) {
				port = 8883
				useTLS = true
				username = "meshdev"
				password = "large4cats"
			} else {
				useTLS = config.tlsEnabled
				port = typedPort ?? (config.tlsEnabled ? 8883 : 1883)
				username = config.username.isEmpty ? nil : config.username
				password = config.password.isEmpty ? nil : config.password
			}
		}
	}

	nonisolated static let defaultDuration: TimeInterval = 60
	nonisolated static let defaultConnectDeadline: TimeInterval = 15
	nonisolated static let defaultSubscribeDeadline: TimeInterval = 10
	/// A flooding broker ends the sample early rather than filling memory.
	nonisolated static let messageCap = 20_000
	/// The region's own /2/e/ stream (~100 msg/s on msh/US) is unsubscribed after this many packets;
	/// the region rung then reads "N+ nodes".
	nonisolated static let regionPacketCap = 300

	let duration: TimeInterval
	let connectDeadline: TimeInterval
	let subscribeDeadline: TimeInterval

	init(duration: TimeInterval = defaultDuration, connectDeadline: TimeInterval = defaultConnectDeadline, subscribeDeadline: TimeInterval = defaultSubscribeDeadline) {
		self.duration = duration
		self.connectDeadline = connectDeadline
		self.subscribeDeadline = subscribeDeadline
		super.init()
	}

	@Published private(set) var phase: Phase = .idle
	/// Snapshot of the tally, republished once a second while sampling and once on finish, so a burst
	/// does not re-render the sheet per packet.
	@Published private(set) var activity: [String: MqttTopicDiscovery.Activity] = [:]
	@Published private(set) var secondsRemaining = 0
	@Published private(set) var messageCount = 0
	private(set) var settings: Settings?
	private(set) var filters: [String] = []
	private(set) var regionTopic = ""
	private var tally = MqttTopicDiscovery.Tally()
	private var regionPackets = 0
	private var client: CocoaMQTT?
	private var deadline: Task<Void, Never>?
	private var countdown: Task<Void, Never>?

	/// Eight filters in one SUBSCRIBE: the region's own map and packet topics, then 2/map and 2/e one to
	/// three levels below it. Never "#": the public broker drops the whole connection for it.
	static func filters(regionTopic: String) -> [String] {
		let levels = ["", "/+", "/+/+", "/+/+/+"]
		return levels.map { regionTopic + $0 + "/2/map/" } + levels.map { regionTopic + $0 + "/2/e/+/+" }
	}

	static func regionPacketFilter(regionTopic: String) -> String {
		regionTopic + "/2/e/+/+"
	}

	func start(settings: Settings, regionTopic: String) {
		beginConnecting(settings: settings, regionTopic: regionTopic)
		openClient()
	}

	/// Everything `start` does except opening the socket: reset, phase = .connecting, arm the connect
	/// deadline. Internal so tests can drive the state machine without a broker.
	func beginConnecting(settings: Settings, regionTopic: String) {
		stop()
		tally = MqttTopicDiscovery.Tally()
		activity = [:]
		messageCount = 0
		regionPackets = 0
		secondsRemaining = 0
		self.settings = settings
		self.regionTopic = regionTopic
		filters = Self.filters(regionTopic: regionTopic)
		phase = .connecting
		let host = settings.host
		armDeadline(connectDeadline) { [weak self] in
			self?.fail(String(localized: "Could not connect to \(host).", comment: "Topic finder: sampler error"))
		}
	}

	/// Ends the sample and keeps what was heard. Idempotent; safe before `start`.
	func stop() {
		switch phase {
		case .connecting, .subscribing, .sampling:
			finish()
		case .idle, .finished, .failed:
			tearDown()
		}
	}

	private func openClient() {
		guard let settings else { return }
		let client = CocoaMQTT(clientID: "MeshtasticAppleTopicFinder-" + UUID().uuidString, host: settings.host, port: settings.port)
		client.enableSSL = settings.useTLS
		client.allowUntrustCACertificate = false
		client.username = settings.username
		client.password = settings.password
		client.keepAlive = 30
		client.cleanSession = true
		// `disconnect()` cannot cancel a pending reconnect timer, so this is never turned on;
		// dropping the instance is what ends it.
		client.autoReconnect = false
		client.backgroundOnSocket = false
		client.delegate = self
		self.client = client
		Logger.mqtt.info("🔎 [MQTT Topics] connect host=\(settings.host, privacy: .public) port=\(settings.port, privacy: .public) tls=\(settings.useTLS, privacy: .public) filters=\(self.filters.count, privacy: .public)")
		guard client.connect(timeout: connectDeadline) else {
			fail(String(localized: "Could not connect to \(settings.host).", comment: "Topic finder: sampler error"))
			return
		}
	}

	// MARK: Main-actor handlers the delegate wrappers call; tests call them directly.

	func handleConnAck(accepted: Bool, description: String) {
		guard phase == .connecting else { return }
		guard accepted else {
			fail(String(localized: "The broker refused the connection: \(description).", comment: "Topic finder: sampler error"))
			return
		}
		cancelDeadline()
		phase = .subscribing
		// Optional chaining is what lets the deadline test run with no client.
		client?.subscribe(filters.map { ($0, CocoaMQTTQoS.qos0) })
		armDeadline(subscribeDeadline) { [weak self] in
			self?.fail(String(localized: "The broker did not confirm the subscription.", comment: "Topic finder: sampler error"))
		}
	}

	func handleSubAck(granted: [String], failed: [String]) {
		guard phase == .subscribing else { return }
		cancelDeadline()
		guard !granted.isEmpty else {
			fail(String(localized: "The broker does not allow these topic filters.", comment: "Topic finder: sampler error"))
			return
		}
		if !failed.isEmpty {
			Logger.mqtt.warning("🔎 [MQTT Topics] filters refused: \(failed.joined(separator: ", "), privacy: .public)")
		}
		filters = filters.filter { granted.contains($0) }
		Logger.mqtt.info("🔎 [MQTT Topics] subscribed granted=\(granted.count, privacy: .public) failed=\(failed.count, privacy: .public)")
		phase = .sampling
		let end = Date().addingTimeInterval(duration)
		secondsRemaining = Int(duration.rounded(.up))
		countdown = Task { @MainActor [weak self] in
			while Date() < end {
				guard let self else { return }
				self.secondsRemaining = Int(end.timeIntervalSinceNow.rounded(.up))
				self.activity = self.tally.activity
				let wait = min(1, end.timeIntervalSinceNow)
				if wait > 0 {
					try? await Task.sleep(for: .seconds(wait))
				}
				if Task.isCancelled { return }
			}
			self?.finish()
		}
	}

	func handleMessage(topic: String, payload: Data) {
		guard phase == .sampling else { return }
		messageCount += 1
		let observation = tally.record(topic: topic, payload: payload)
		if let observation, observation.root == regionTopic, case .packet = observation.kind {
			regionPackets += 1
			if regionPackets == Self.regionPacketCap {
				let filter = Self.regionPacketFilter(regionTopic: regionTopic)
				client?.unsubscribe(filter)
				tally.markTruncated(regionTopic)
				Logger.mqtt.info("🔎 [MQTT Topics] region packet cap reached, unsubscribed \(filter, privacy: .public)")
			}
		}
		if messageCount >= Self.messageCap {
			finish()
		}
	}

	func handleDisconnect(error: Error?) {
		switch phase {
		case .connecting:
			// The socket's own text ("nodename nor servname provided", "Connection refused") goes
			// to the log; the user sees the same message as the connect deadline.
			let host = settings?.host ?? ""
			if let error {
				Logger.mqtt.error("🔎 [MQTT Topics] connect to \(host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
			}
			fail(String(localized: "Could not connect to \(host).", comment: "Topic finder: sampler error"))
		case .subscribing:
			// This is how mqtt.meshtastic.org says no: socket closed, no SUBACK.
			fail(String(localized: "The broker does not allow these topic filters.", comment: "Topic finder: sampler error"))
		case .sampling:
			if messageCount > 0 {
				// Partial results are still useful.
				finish()
			} else {
				fail(String(localized: "The broker closed the connection.", comment: "Topic finder: sampler error"))
			}
		case .idle, .finished, .failed:
			return
		}
	}

	// MARK: Ending

	private func finish() {
		activity = tally.activity
		secondsRemaining = 0
		phase = .finished
		Logger.mqtt.info("🔎 [MQTT Topics] finished messages=\(self.messageCount, privacy: .public) roots=\(self.tally.activity.count, privacy: .public) dropped=\(self.tally.droppedRoots, privacy: .public)")
		tearDown()
	}

	private func fail(_ message: String) {
		activity = tally.activity
		phase = .failed(message)
		Logger.mqtt.error("🔎 [MQTT Topics] failed: \(message, privacy: .public)")
		tearDown()
	}

	/// Dropping the client is what cancels CocoaMQTT's timers (`deinit` is its only cancel path); the
	/// delegate is cleared first so a late callback cannot touch a finished sampler.
	private func tearDown() {
		cancelDeadline()
		countdown?.cancel()
		countdown = nil
		client?.delegate = nil
		client?.disconnect()
		client = nil
	}

	private func armDeadline(_ seconds: TimeInterval, _ onExpiry: @escaping @MainActor () -> Void) {
		cancelDeadline()
		deadline = Task { @MainActor in
			try? await Task.sleep(for: .seconds(seconds))
			if Task.isCancelled { return }
			onExpiry()
		}
	}

	private func cancelDeadline() {
		deadline?.cancel()
		deadline = nil
	}
}

/// The wrappers are `nonisolated` to satisfy the `@objc` protocol and hop back onto the main actor
/// with `assumeIsolated`, which `delegateQueue = .main` makes true.
extension MqttTopicSampler: CocoaMQTTDelegate {
	nonisolated func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
		let description: String
		switch ack {
		case .accept:
			description = "No Error"
		case .unacceptableProtocolVersion:
			description = "Unacceptable Protocol version"
		case .identifierRejected:
			description = "Invalid Id"
		case .serverUnavailable:
			description = "Invalid Server"
		case .badUsernameOrPassword:
			description = "Invalid Credentials"
		case .notAuthorized:
			description = "Authorization Error"
		default:
			description = "Unknown Error"
		}
		MainActor.assumeIsolated {
			handleConnAck(accepted: ack == .accept, description: description)
		}
	}

	nonisolated func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
		let topic = message.topic
		let payload = Data(message.payload)
		MainActor.assumeIsolated {
			handleMessage(topic: topic, payload: payload)
		}
	}

	nonisolated func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
		let granted = success.allKeys as? [String] ?? []
		MainActor.assumeIsolated {
			handleSubAck(granted: granted, failed: failed)
		}
	}

	nonisolated func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
		MainActor.assumeIsolated {
			handleDisconnect(error: err)
		}
	}

	nonisolated func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
		completionHandler(SecTrustEvaluateWithError(trust, nil))
	}

	nonisolated func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
		Logger.mqtt.info("🔎 [MQTT Topics] unsubscribed \(topics.joined(separator: ", "), privacy: .public)")
	}

	nonisolated func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}

	nonisolated func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

	nonisolated func mqttDidPing(_ mqtt: CocoaMQTT) {}

	nonisolated func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}
