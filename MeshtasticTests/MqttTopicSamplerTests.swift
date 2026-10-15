//
//  MqttTopicSamplerTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/11/26.
//

import Foundation
@testable import Meshtastic
import MeshtasticProtobufs
import Testing

/// No socket: `start` is never called. `beginConnecting` and the handlers drive the state machine.
@Suite("MQTT topic sampler")
@MainActor
struct MqttTopicSamplerTests {

	private let region = "msh/US"

	private func makeSampler() -> MqttTopicSampler {
		MqttTopicSampler(duration: 0.3, connectDeadline: 0.2, subscribeDeadline: 0.2)
	}

	private func settings(address: String = "mqtt.meshtastic.org", tls: Bool = true, username: String = "", password: String = "") -> MqttTopicSampler.Settings {
		var config = ModuleConfig.MQTTConfig()
		config.address = address
		config.tlsEnabled = tls
		config.username = username
		config.password = password
		return MqttTopicSampler.Settings(config: config)
	}

	private func waitUntil(timeout: Duration = .seconds(1), _ condition: @escaping () -> Bool) async {
		let deadline = ContinuousClock.now + timeout
		while !condition(), ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	private func isFailed(_ phase: MqttTopicSampler.Phase) -> Bool {
		if case .failed = phase { return true }
		return false
	}

	private func failureMessage(_ phase: MqttTopicSampler.Phase) -> String? {
		if case .failed(let message) = phase { return message }
		return nil
	}

	/// Drives a fresh sampler to `.sampling` with every filter granted.
	private func sampling() -> MqttTopicSampler {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		sampler.handleConnAck(accepted: true, description: "")
		sampler.handleSubAck(granted: sampler.filters, failed: [])
		return sampler
	}

	@Test func filtersForRegion() {
		let filters = MqttTopicSampler.filters(regionTopic: region)
		#expect(filters == [
			"msh/US/2/map/", "msh/US/+/2/map/", "msh/US/+/+/2/map/", "msh/US/+/+/+/2/map/",
			"msh/US/2/e/+/+", "msh/US/+/2/e/+/+", "msh/US/+/+/2/e/+/+", "msh/US/+/+/+/2/e/+/+"
		])
		#expect(!filters.contains { $0.contains("#") })
		#expect(MqttTopicSampler.regionPacketFilter(regionTopic: region) == filters[4])
	}

	@Test func settingsFromConfig() {
		let publicServer = settings(username: "typed", password: "secret")
		#expect(publicServer.host == "mqtt.meshtastic.org")
		#expect(publicServer.port == 8883)
		#expect(publicServer.useTLS)
		#expect(publicServer.username == "meshdev")
		#expect(publicServer.password == "large4cats")

		let upperWithPort = settings(address: "MQTT.meshtastic.org:1883", tls: false)
		#expect(upperWithPort.port == 8883)
		#expect(upperWithPort.useTLS)

		let privatePlain = settings(address: "broker.local:1884", tls: false, username: "a", password: "b")
		#expect(privatePlain.host == "broker.local")
		#expect(privatePlain.port == 1884)
		#expect(!privatePlain.useTLS)
		#expect(privatePlain.username == "a")
		#expect(privatePlain.password == "b")

		let privateTLS = settings(address: "broker.local", tls: true)
		#expect(privateTLS.port == 8883)
		#expect(privateTLS.useTLS)
		#expect(privateTLS.username == nil)
		#expect(privateTLS.password == nil)

		#expect(settings(address: "").host == "mqtt.meshtastic.org")
		#expect(settings(address: "   ").host == "mqtt.meshtastic.org")

		let lookalike = settings(address: "mqtt.meshtastic.org.example.com", tls: false, username: "a")
		#expect(lookalike.port == 1883)
		#expect(!lookalike.useTLS)
		#expect(lookalike.username == "a")
	}

	@Test func beginConnectingArmsTheConnectDeadline() async {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		#expect(sampler.phase == .connecting)
		await waitUntil { sampler.phase != .connecting }
		#expect(isFailed(sampler.phase))
		#expect(failureMessage(sampler.phase)?.contains("mqtt.meshtastic.org") == true)
	}

	@Test func connAckStartsTheSubscribeDeadline() async {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		sampler.handleConnAck(accepted: true, description: "")
		#expect(sampler.phase == .subscribing)
		await waitUntil { sampler.phase != .subscribing }
		#expect(sampler.phase == .failed("The broker did not confirm the subscription."))
	}

	@Test func connAckRefusedFails() {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		sampler.handleConnAck(accepted: false, description: "Invalid Credentials")
		#expect(failureMessage(sampler.phase)?.contains("Invalid Credentials") == true)
	}

	@Test func subAckWithNothingGrantedFails() {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		sampler.handleConnAck(accepted: true, description: "")
		sampler.handleSubAck(granted: [], failed: sampler.filters)
		#expect(sampler.phase == .failed("The broker does not allow these topic filters."))
	}

	@Test func partialSubAckKeepsGrantedFilters() {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		sampler.handleConnAck(accepted: true, description: "")
		let granted = Array(sampler.filters.prefix(2))
		sampler.handleSubAck(granted: granted, failed: Array(sampler.filters.dropFirst(2)))
		#expect(sampler.phase == .sampling)
		#expect(sampler.filters == granted)
		#expect(sampler.secondsRemaining > 0)
		sampler.stop()
	}

	@Test func countdownFinishes() async {
		let sampler = sampling()
		#expect(sampler.phase == .sampling)
		await waitUntil { sampler.phase == .finished }
		#expect(sampler.phase == .finished)
		#expect(sampler.secondsRemaining == 0)
	}

	@Test func messagesTallyOnlyWhileSampling() {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		sampler.handleMessage(topic: "msh/US/WA/2/e/LongFast/!ab12cd34", payload: Data())
		#expect(sampler.messageCount == 0)
		sampler.stop()

		let live = sampling()
		live.handleMessage(topic: "msh/US/WA/2/e/LongFast/!ab12cd34", payload: Data())
		live.stop()
		#expect(live.phase == .finished)
		#expect(live.messageCount == 1)
		#expect(live.activity["msh/US/WA"]?.nodeCount == 1)
	}

	@Test func junkCountsAsMessageButNotActivity() {
		let sampler = sampling()
		sampler.handleMessage(topic: "HQ-Gateway-1/node/!x", payload: Data([1]))
		sampler.stop()
		#expect(sampler.messageCount == 1)
		#expect(sampler.activity.isEmpty)
	}

	@Test func regionCapMarksTruncated() {
		let sampler = sampling()
		for _ in 0..<MqttTopicSampler.regionPacketCap {
			sampler.handleMessage(topic: "msh/US/2/e/LongFast/!ab12cd34", payload: Data())
		}
		sampler.stop()
		#expect(sampler.activity["msh/US"]?.truncated == true)
		#expect(sampler.activity["msh/US"]?.packets == MqttTopicSampler.regionPacketCap)
	}

	@Test func disconnectWhileConnectingShowsTheHostNotTheSocketError() {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(address: "nope.invalid", tls: false), regionTopic: region)
		let socketError = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNREFUSED), userInfo: [NSLocalizedDescriptionKey: "Connection refused"])
		sampler.handleDisconnect(error: socketError)
		#expect(sampler.phase == .failed("Could not connect to nope.invalid."))
	}

	@Test func disconnectWhileSubscribingIsARefusal() {
		let sampler = makeSampler()
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		sampler.handleConnAck(accepted: true, description: "")
		sampler.handleDisconnect(error: nil)
		#expect(sampler.phase == .failed("The broker does not allow these topic filters."))
	}

	@Test func disconnectMidSampleKeepsResults() {
		let heard = sampling()
		heard.handleMessage(topic: "msh/US/WA/2/map/", payload: Data())
		heard.handleDisconnect(error: nil)
		#expect(heard.phase == .finished)
		#expect(heard.activity["msh/US/WA"]?.mapReports == 1)

		let silent = sampling()
		silent.handleDisconnect(error: nil)
		#expect(silent.phase == .failed("The broker closed the connection."))
	}

	@Test func stopIsIdempotent() {
		let idle = makeSampler()
		idle.stop()
		idle.stop()
		#expect(idle.phase == .idle)

		let finished = sampling()
		finished.handleMessage(topic: "msh/US/WA/2/map/", payload: Data())
		finished.stop()
		finished.stop()
		#expect(finished.phase == .finished)
		finished.handleDisconnect(error: nil)
		#expect(finished.phase == .finished)
		#expect(finished.activity["msh/US/WA"]?.mapReports == 1)
	}

	@Test func messageCapEndsSample() {
		let sampler = sampling()
		for _ in 0..<MqttTopicSampler.messageCap {
			sampler.handleMessage(topic: "HQ-Gateway-1/node/!x", payload: Data())
		}
		#expect(sampler.phase == .finished)
		#expect(sampler.messageCount == MqttTopicSampler.messageCap)
	}

	@Test func restartResets() {
		let sampler = sampling()
		sampler.handleMessage(topic: "msh/US/WA/2/map/", payload: Data())
		sampler.stop()
		#expect(sampler.phase == .finished)
		#expect(!sampler.activity.isEmpty)
		sampler.beginConnecting(settings: settings(), regionTopic: region)
		#expect(sampler.phase == .connecting)
		#expect(sampler.activity.isEmpty)
		#expect(sampler.messageCount == 0)
		sampler.stop()
	}
}
