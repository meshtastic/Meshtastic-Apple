import Foundation
import Testing
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Remote Channels")
struct RemoteChannelsTests {
	@Test("remote channel identity includes the target name and node number")
	func remoteTargetIdentityIsAccessible() {
		let label = RemoteTargetIdentity.accessibilityLabel(name: "Relay Alpha", nodeNum: 0x1234)

		#expect(label.contains("Relay Alpha"))
		#expect(label.contains("4660"))
	}

    @Test("channel read requests use one based wire indexes")
    func channelReadRequestUsesOneBasedWireIndex() throws {
        let packet = try RemoteChannelsPacketBuilder.getRequest(
            index: 0, from: 0x1111, to: 0x2222, sessionPasskey: Data([1, 2, 3]), id: 42
        )
        let admin = try AdminMessage(serializedBytes: packet.decoded.payload)

        #expect(admin.getChannelRequest == 1)
        #expect(packet.to == 0x2222)
        #expect(packet.from == 0x1111)
        #expect(admin.sessionPasskey == Data([1, 2, 3]))
        #expect(packet.decoded.wantResponse)
    }

    @Test("channel read requests reject indexes outside the firmware slot range")
    func channelReadRequestRejectsInvalidIndex() {
        #expect(throws: AccessoryError.self) {
            _ = try RemoteChannelsPacketBuilder.getRequest(
                index: 8, from: 0x1111, to: 0x2222, sessionPasskey: Data(), id: 42
            )
        }
    }

    @Test("channel writes carry the session key and request an acknowledgement")
    func channelWriteRequestUsesFirmwareEnvelope() throws {
        var channel = Channel()
        channel.index = 2
        channel.role = .secondary
        channel.settings.name = "Remote"
        channel.settings.psk = Data(repeating: 7, count: 16)
        let packet = try RemoteChannelsPacketBuilder.setRequest(
            channel: channel, from: 0x1111, to: 0x2222, sessionPasskey: Data([1, 2, 3]), id: 43
        )
        let admin = try AdminMessage(serializedBytes: packet.decoded.payload)

        #expect(admin.setChannel == channel)
        #expect(admin.sessionPasskey == Data([1, 2, 3]))
        #expect(packet.wantAck)
        #expect(packet.decoded.wantResponse)
    }

    @Test("response matching isolates target and request index")
    func responseMatchingIsTargetScoped() throws {
        var channel = Channel()
        channel.index = 3
        var response = AdminMessage()
        response.getChannelResponse = channel

        var packet = MeshPacket()
        packet.from = 0x2222
        packet.to = 0x1111
        packet.decoded.requestID = 99

        #expect(RemoteChannelsPacketBuilder.matchesResponse(
            packet: packet, response: response, requestID: 99, target: 0x2222, index: 3
        ))
        #expect(!RemoteChannelsPacketBuilder.matchesResponse(
            packet: packet, response: response, requestID: 99, target: 0x3333, index: 3
        ))
        #expect(!RemoteChannelsPacketBuilder.matchesResponse(
            packet: packet, response: response, requestID: 99, target: 0x2222, index: 2
        ))
    }

    @Test("ordered writes stop at the first failure")
    func orderedWritesStopAtFirstFailure() async throws {
        let channels = [0, 1, 2].map { index in
            var channel = Channel()
            channel.index = Int32(index)
            return channel
        }
        var attempted: [Int32] = []
        let result = try await RemoteChannelsWritePlan.execute(channels) { channel in
            attempted.append(channel.index)
            if channel.index == 1 { throw AccessoryError.ioFailed("failed") }
        }

        #expect(attempted == [0, 1])
        #expect(result == .failure(index: 1))
    }

    @Test("remote reads retry once and surface timeout when every attempt fails")
    func remoteReadsRetryAndSurfaceTimeout() async {
        var attempts = 0
        let value = try? await RemoteChannelsReadPlan.retry(retries: 1) {
            attempts += 1
            if attempts == 1 { throw AccessoryError.timeout }
            return "confirmed"
        }
        #expect(value == "confirmed")
        #expect(attempts == 2)

        let timedOut = try? await RemoteChannelsReadPlan.retry(retries: 1) {
            throw AccessoryError.timeout
        }
        #expect(timedOut == nil)
    }

	@MainActor
	@Test("coordinator confirms editable fields and stops after a mismatch")
	func coordinatorReadbackMismatchStopsWrites() async throws {
		let transport = TestRemoteChannelsTransport()
		transport.session = true
		var first = Channel(); first.index = 0; first.role = .primary; first.settings.name = "Before"
		transport.channels[0] = first
		let coordinator = RemoteChannelsCoordinator(transport: transport, sourceNum: 1, targetNum: 2)
		transport.onRequest = { [weak coordinator] id, channel in
			var response = channel
			if channel.index == 0 { response.settings.name = "Different" }
			coordinator?.receive(TestRemoteChannelsTransport.notification(id: id, source: 2, destination: 1, channel: response))
		}
		var desired = first; desired.settings.name = "After"
		await #expect(throws: AccessoryError.self) { try await coordinator.save([desired]) }
		#expect(transport.saveCount == 1)
	}

	@MainActor
	@Test("coordinator refreshes initial PKI session before loading")
	func coordinatorRefreshesBeforeLoad() async throws {
		let transport = TestRemoteChannelsTransport()
		let coordinator = RemoteChannelsCoordinator(transport: transport, sourceNum: 1, targetNum: 2)
		transport.onRequest = { [weak coordinator] id, channel in
			coordinator?.receive(TestRemoteChannelsTransport.notification(id: id, source: 2, destination: 1, channel: channel))
		}
		var primary = Channel(); primary.index = 0; primary.role = .primary; primary.settings.name = "Primary"; primary.settings.moduleSettings.isMuted = true
		transport.channels[0] = primary
		try await coordinator.load()
		#expect(transport.refreshCount == 1)
		#expect(coordinator.channels[0]?.role == .primary)
		#expect(coordinator.channels[0]?.settings.name == "Primary")
		#expect(coordinator.channels[0]?.settings.moduleSettings.isMuted == true)
	}

	@MainActor
	@Test("coordinator refreshes a rejected session before retrying a channel read")
	func coordinatorRefreshesAfterRejectedRead() async throws {
		let transport = TestRemoteChannelsTransport()
		transport.session = true
		transport.rejectNextRequest = true
		let coordinator = RemoteChannelsCoordinator(transport: transport, sourceNum: 1, targetNum: 2)
		transport.onRequest = { [weak coordinator] id, channel in
			coordinator?.receive(TestRemoteChannelsTransport.notification(id: id, source: 2, destination: 1, channel: channel))
		}

		var primary = Channel()
		primary.index = 0
		primary.role = .primary
		transport.channels[0] = primary
		try await coordinator.load()

		#expect(transport.refreshCount == 1)
		#expect(coordinator.channels[0]?.role == .primary)
	}

	@MainActor
	@Test("coordinator reports a real no reply timeout")
	func coordinatorNoReplyTimesOut() async {
		let transport = TestRemoteChannelsTransport(); transport.session = true
		let coordinator = RemoteChannelsCoordinator(transport: transport, sourceNum: 1, targetNum: 2)
		await #expect(throws: AccessoryError.self) { try await coordinator.load() }
	}

	@MainActor
	@Test("coordinator aborts when the connected identity switches")
	func coordinatorAbortsOnIdentitySwitch() async {
		let transport = TestRemoteChannelsTransport(); transport.session = true
		let coordinator = RemoteChannelsCoordinator(transport: transport, sourceNum: 1, targetNum: 2)
		transport.onRequest = { _, _ in transport.switchConnection() }
		await #expect(throws: AccessoryError.self) { try await coordinator.load() }
	}

	@MainActor
	@Test("coordinator confirms a successful save with semantic fields")
	func coordinatorConfirmsSuccessfulSave() async throws {
		let transport = TestRemoteChannelsTransport(); transport.session = true
		let coordinator = RemoteChannelsCoordinator(transport: transport, sourceNum: 1, targetNum: 2)
		transport.onRequest = { [weak coordinator] id, channel in
			coordinator?.receive(TestRemoteChannelsTransport.notification(id: id, source: 2, destination: 1, channel: channel))
		}
		var channel = Channel(); channel.index = 1; channel.role = .secondary
		channel.settings.name = "Remote"; channel.settings.psk = Data(repeating: 7, count: 16)
		channel.settings.uplinkEnabled = true; channel.settings.downlinkEnabled = true
		channel.settings.moduleSettings.positionPrecision = 14; channel.settings.moduleSettings.isMuted = true
		try await coordinator.save([channel])
		#expect(transport.saveCount == 1)
		#expect(coordinator.channels[1]?.settings.moduleSettings.isMuted == true)
	}

	@MainActor
	@Test("disabled channel writes clear settings and invalid roles are rejected")
	func disabledAndInvalidRoles() async throws {
		let transport = TestRemoteChannelsTransport(); transport.session = true
		let coordinator = RemoteChannelsCoordinator(transport: transport, sourceNum: 1, targetNum: 2)
		transport.onRequest = { [weak coordinator] id, channel in
			coordinator?.receive(TestRemoteChannelsTransport.notification(id: id, source: 2, destination: 1, channel: channel))
		}
		var disabled = Channel(); disabled.index = 1; disabled.role = .disabled; disabled.settings.name = "old"
		try await coordinator.save([disabled])
		#expect(transport.channels[1]?.hasSettings == false)
		var primaryOnSecondary = Channel(); primaryOnSecondary.index = 1; primaryOnSecondary.role = .primary
		await #expect(throws: AccessoryError.self) { try await coordinator.save([primaryOnSecondary]) }
		var disabledPrimary = Channel(); disabledPrimary.index = 0; disabledPrimary.role = .disabled
		await #expect(throws: AccessoryError.self) { try await coordinator.save([disabledPrimary]) }
	}
}

private final class IdentityToken {}

@MainActor
private final class TestRemoteChannelsTransport: RemoteChannelsTransport {
	var isConnected = true
	var connectedDeviceNum: Int64? = 1
	var identityToken = IdentityToken()
	var connectionID: ObjectIdentifier? { ObjectIdentifier(identityToken) }
	var session = false
	var refreshCount = 0
	var saveCount = 0
	var rejectNextRequest = false
	var channels: [Int32: Channel] = [:]
	var onRequest: ((UInt32, Channel) -> Void)?
	private var nextID: UInt32 = 100
	var hasLiveSession: Bool { session }
	func switchConnection() { identityToken = IdentityToken() }
	var responseTimeout: Duration { .milliseconds(50) }
	var sessionTimeout: Duration { .milliseconds(50) }

	func refreshMetadata() async throws { refreshCount += 1; session = true }
	func requestChannel(index: Int32) async throws -> UInt32 {
		guard session else { throw AccessoryError.ioFailed("Remote admin session expired") }
		let id = nextID; nextID += 1
		if rejectNextRequest {
			rejectNextRequest = false
			session = false
			throw AccessoryError.ioFailed("Remote node rejected the request: adminBadSessionKey")
		}
		var channel = channels[index] ?? Channel()
		channel.index = index
		onRequest?(id, channel)
		return id
	}
	func saveChannel(_ channel: Channel) async throws { saveCount += 1; channels[channel.index] = channel }

	static func notification(id: UInt32, source: UInt32, destination: UInt32, channel: Channel) -> Foundation.Notification {
		var response = AdminMessage(); response.getChannelResponse = channel
		var packet = MeshPacket(); packet.from = source; packet.to = destination; packet.decoded.requestID = id
		return Foundation.Notification(name: .remoteChannelResponse, object: nil, userInfo: ["packet": packet, "response": response])
	}
}
