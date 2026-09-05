import Foundation
import MeshtasticProtobufs
import SwiftUI

enum RemoteChannelsPacketBuilder {
    static func getRequest(index: Int32, from: UInt32, to: UInt32, sessionPasskey: Data, id: UInt32 = .random(in: 256...UInt32.max)) throws -> MeshPacket {
        precondition((0...7).contains(index))
        var admin = AdminMessage()
        admin.getChannelRequest = UInt32(index + 1)
        admin.sessionPasskey = sessionPasskey
        var packet = MeshPacket()
        packet.id = id
        packet.from = from
        packet.to = to
        packet.priority = .reliable
        packet.wantAck = true
        var data = DataMessage()
        data.payload = try admin.serializedData()
        data.portnum = .adminApp
        data.wantResponse = true
        packet.decoded = data
        return packet
    }

    static func matchesResponse(packet: MeshPacket, response: AdminMessage, requestID: UInt32, target: UInt32, index: Int32) -> Bool {
        guard packet.from == target, packet.decoded.requestID == requestID else { return false }
        guard case .getChannelResponse(let channel) = response.payloadVariant else { return false }
        return channel.index == index
    }
}

enum RemoteChannelsWriteResult: Equatable {
    case success
    case failure(index: Int32)
}

enum RemoteChannelsWritePlan {
    static func execute(_ channels: [Channel], write: (Channel) async throws -> Void) async throws -> RemoteChannelsWriteResult {
        for channel in channels.sorted(by: { $0.index < $1.index }) {
            do {
                try await write(channel)
            } catch {
                if error is CancellationError { throw error }
                return .failure(index: Int32(channel.index))
            }
        }
        return .success
    }
}

enum RemoteChannelsReadPlan {
    static func retry<T>(retries: Int, operation: () async throws -> T) async throws -> T {
        var lastError: Error = AccessoryError.timeout
        for attempt in 0...retries {
            do { return try await operation() }
			catch {
				if error is CancellationError { throw error }
				if case AccessoryError.disconnected = error { throw error }
                lastError = error
                if attempt == retries { throw lastError }
            }
        }
        throw lastError
    }
}

extension Foundation.Notification.Name {
    static let remoteChannelResponse = Foundation.Notification.Name("Meshtastic.RemoteChannelResponse")
}

@MainActor
protocol RemoteChannelsTransport {
	var isConnected: Bool { get }
	var connectedDeviceNum: Int64? { get }
	var connectionID: ObjectIdentifier? { get }
	var hasLiveSession: Bool { get }
	var responseTimeout: Duration { get }
	var sessionTimeout: Duration { get }
	func refreshMetadata() async throws
	func requestChannel(index: Int32) async throws -> UInt32
	func saveChannel(_ channel: Channel) async throws
}

@MainActor
final class AccessoryManagerRemoteChannelsTransport: RemoteChannelsTransport {
	private let manager: AccessoryManager
	private let fromUser: UserEntity
	private let toUser: UserEntity

	init(manager: AccessoryManager, fromUser: UserEntity, toUser: UserEntity) {
		self.manager = manager
		self.fromUser = fromUser
		self.toUser = toUser
	}

	var isConnected: Bool { manager.isConnected }
	var connectedDeviceNum: Int64? { manager.activeDeviceNum }
	var connectionID: ObjectIdentifier? {
		guard let connection = manager.activeConnection?.connection else { return nil }
		return ObjectIdentifier(connection)
	}
	var hasLiveSession: Bool { toUser.userNode?.hasLiveAdminSession == true }
	var responseTimeout: Duration { .seconds(30) }
	var sessionTimeout: Duration { .seconds(30) }
	func refreshMetadata() async throws { _ = try await manager.requestDeviceMetadata(fromUser: fromUser, toUser: toUser) }
	func requestChannel(index: Int32) async throws -> UInt32 {
		try await manager.requestRemoteChannel(index: index, fromUser: fromUser, toUser: toUser)
	}
	func saveChannel(_ channel: Channel) async throws {
		_ = try await manager.saveChannel(channel: channel, fromUser: fromUser, toUser: toUser)
	}
}

@MainActor
final class RemoteChannelsCoordinator: ObservableObject {
    @Published private(set) var channels: [Int32: Channel] = [:]
    @Published private(set) var progress: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false

	private let transport: any RemoteChannelsTransport
	private let sourceConnectionID: ObjectIdentifier?
    private var responses: [(requestID: UInt32, target: UInt32, channel: Channel)] = []
    private let sourceNum: Int64
    private let targetNum: Int64

	init(transport: any RemoteChannelsTransport, sourceNum: Int64, targetNum: Int64) {
		self.transport = transport
		self.sourceNum = sourceNum
		self.targetNum = targetNum
		self.sourceConnectionID = transport.connectionID
    }

    func receive(_ notification: Foundation.Notification) {
        guard let packet = notification.userInfo?["packet"] as? MeshPacket,
              let response = notification.userInfo?["response"] as? AdminMessage,
              case .getChannelResponse(let channel) = response.payloadVariant,
				packet.from == UInt32(targetNum), packet.to == UInt32(sourceNum) else { return }
        responses.append((packet.decoded.requestID, packet.from, channel))
    }

    func load() async throws {
        try validateConnection()
        isLoading = true
        progress = 0
        defer { isLoading = false }
        try await refreshSessionIfNeeded()
        var loaded: [Int32: Channel] = [:]
        for index in Int32(0)...Int32(7) {
            try Task.checkCancellation()
            try validateConnection()
            let channel = try await read(index: index, retries: 1)
            loaded[index] = channel
            progress = Int(index) + 1
        }
        channels = loaded
    }

    func save(_ changed: [Channel]) async throws {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        try Task.checkCancellation()
        try validateConnection()
        try await refreshSessionIfNeeded()
		let result = try await RemoteChannelsWritePlan.execute(changed) { [weak self] channel in
			guard let self else { throw AccessoryError.disconnected("Remote Channels was closed") }
			try self.validateEditableChannel(channel)
			var outgoing = channel
			if outgoing.role == .disabled { outgoing.clearSettings() }
			try Task.checkCancellation()
			try self.validateConnection()
			try await self.transport.saveChannel(outgoing)
			let actual = try await self.read(index: Int32(outgoing.index), retries: 1)
			guard self.matchesEditableChannel(actual, desired: outgoing) else {
				throw AccessoryError.ioFailed("Remote channel \(channel.index) did not match the saved values")
			}
            self.channels[Int32(channel.index)] = actual
        }
        if case .failure(let index) = result {
            throw AccessoryError.ioFailed("Remote channel \(index) was not confirmed")
        }
    }

    private func read(index: Int32, retries: Int) async throws -> Channel {
        try await RemoteChannelsReadPlan.retry(retries: retries) {
                try Task.checkCancellation()
                try self.validateConnection()
				let requestID = try await transport.requestChannel(index: index)
				let deadline = ContinuousClock.now + transport.responseTimeout
                while ContinuousClock.now < deadline {
                    try Task.checkCancellation()
                    try self.validateConnection()
					if let match = responses.firstIndex(where: { $0.requestID == requestID && $0.target == UInt32(targetNum) && $0.channel.index == index }) {
                        return responses.remove(at: match).channel
                    }
                    try await Task.sleep(for: .milliseconds(50))
                }
                throw AccessoryError.timeout
        }
    }

    private func refreshSessionIfNeeded() async throws {
		// Remote Channels requires a live PKI administration session before any slot access.
		guard !transport.hasLiveSession else { return }
		try validateConnection()
		try await transport.refreshMetadata()
		let deadline = ContinuousClock.now + transport.sessionTimeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try validateConnection()
			if transport.hasLiveSession { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw AccessoryError.ioFailed("Remote admin session expired; refresh the node and try again")
    }

	private func validateConnection() throws {
		guard transport.isConnected, transport.connectedDeviceNum == sourceNum,
			  transport.connectionID == sourceConnectionID else {
			throw AccessoryError.disconnected("The connected radio changed or disconnected")
		}
	}

	private func validateEditableChannel(_ channel: Channel) throws {
		guard (0...7).contains(channel.index) else { throw AccessoryError.appError("Channel index must be between 0 and 7") }
		guard channel.index == 0 ? channel.role == .primary : channel.role != .primary else {
			throw AccessoryError.appError("Only channel 0 can be primary")
		}
		guard channel.settings.name.utf8.count <= 11 else { throw AccessoryError.appError("Channel names must be 11 bytes or fewer") }
		guard [0, 1, 16, 32].contains(channel.settings.psk.count) else { throw AccessoryError.appError("Channel key has an unsupported length") }
	}

	private func matchesEditableChannel(_ actual: Channel, desired: Channel) -> Bool {
		guard actual.index == desired.index, actual.role == desired.role else { return false }
		guard desired.role != .disabled else { return true }
		return actual.settings.name == desired.settings.name &&
			actual.settings.psk == desired.settings.psk &&
			actual.settings.uplinkEnabled == desired.settings.uplinkEnabled &&
			actual.settings.downlinkEnabled == desired.settings.downlinkEnabled &&
			actual.settings.moduleSettings.positionPrecision == desired.settings.moduleSettings.positionPrecision &&
			actual.settings.moduleSettings.isMuted == desired.settings.moduleSettings.isMuted
	}
	}

struct RemoteChannels: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accessoryManager: AccessoryManager
    let node: NodeInfoEntity
    let connectedNode: NodeInfoEntity
    let fromUser: UserEntity
    let toUser: UserEntity
    @StateObject private var coordinator: RemoteChannelsCoordinator
    @State private var selected: Channel?
    @State private var errorMessage: String?

    init(node: NodeInfoEntity, connectedNode: NodeInfoEntity, fromUser: UserEntity, toUser: UserEntity, accessoryManager: AccessoryManager) {
        self.node = node
        self.connectedNode = connectedNode
        self.fromUser = fromUser
        self.toUser = toUser
		self.accessoryManager = accessoryManager
		_coordinator = StateObject(wrappedValue: RemoteChannelsCoordinator(
			transport: AccessoryManagerRemoteChannelsTransport(manager: accessoryManager, fromUser: fromUser, toUser: toUser),
			sourceNum: fromUser.num, targetNum: toUser.num
		))
    }

    var body: some View {
        List {
            if coordinator.isLoading {
                ProgressView("Reading remote channels (\(coordinator.progress)/8)…")
            }
            ForEach(Int32(0)...Int32(7), id: \.self) { index in
                if let channel = coordinator.channels[index] {
                    Button {
                        selected = channel
                    } label: {
                        HStack {
                            Text(channel.settings.name.isEmpty ? "Channel \(index)" : channel.settings.name)
                            Spacer()
                            Text(channel.role == .primary ? "Primary" : channel.role == .disabled ? "Disabled" : "Secondary")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Remote Channels")
        .task {
            do { try await coordinator.load() }
            catch { errorMessage = error.localizedDescription }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Retry") {
                    Task {
                        do { try await coordinator.load(); errorMessage = nil }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .disabled(coordinator.isLoading || coordinator.isSaving)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteChannelResponse).receive(on: RunLoop.main)) { coordinator.receive($0) }
        .alert("Remote Channels", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let channel = selected {
                RemoteChannelEditor(channel: channel, isSaving: coordinator.isSaving) { edited in
                    try await coordinator.save([edited])
                    selected = nil
                }
            }
        }
    }
}

struct RemoteChannelsUnavailable: View {
	let nodeName: String

	var body: some View {
		VStack(spacing: 12) {
			Image(systemName: "lock.slash").font(.largeTitle).foregroundStyle(.secondary)
			Text("Remote Channels Unavailable").font(.headline)
			Text("\(nodeName) does not have a live PKI administration session. Refresh node administration and try again.")
				.multilineTextAlignment(.center).foregroundStyle(.secondary)
		}
		.padding()
		.navigationTitle("Remote Channels")
	}
}

private struct RemoteChannelEditor: View {
    @Environment(\.dismiss) private var dismiss
    let channel: Channel
    let isSaving: Bool
    let onSave: (Channel) async throws -> Void
    @State private var name: String
    @State private var key: String
    @State private var role: Channel.Role
    @State private var uplink: Bool
    @State private var downlink: Bool
    @State private var precision: Int
    @State private var muted: Bool
    @State private var errorMessage: String?

    init(channel: Channel, isSaving: Bool, onSave: @escaping (Channel) async throws -> Void) {
        self.channel = channel
        self.isSaving = isSaving
        self.onSave = onSave
        _name = State(initialValue: channel.settings.name)
        _key = State(initialValue: channel.settings.psk.base64EncodedString())
        _role = State(initialValue: channel.role)
        _uplink = State(initialValue: channel.settings.uplinkEnabled)
        _downlink = State(initialValue: channel.settings.downlinkEnabled)
        _precision = State(initialValue: Int(channel.settings.moduleSettings.positionPrecision))
        _muted = State(initialValue: channel.settings.moduleSettings.isMuted)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .onChange(of: name) { _, value in
                        let compact = value.replacingOccurrences(of: " ", with: "")
                        var limited = ""
                        for scalar in compact.unicodeScalars {
                            guard limited.utf8.count + String(scalar).utf8.count <= 11 else { break }
                            limited.append(String(scalar))
                        }
                        name = limited
                    }
                TextField("Key (base64)", text: $key)
                    .textSelection(.enabled)
                Picker("Role", selection: $role) {
                    if channel.index == 0 {
                        Text("Primary").tag(Channel.Role.primary)
                    } else {
                        Text("Secondary").tag(Channel.Role.secondary)
                        Text("Disabled").tag(Channel.Role.disabled)
                    }
                }
                Toggle("MQTT Uplink Enabled", isOn: $uplink)
                Toggle("MQTT Downlink Enabled", isOn: $downlink)
                Toggle("Mute", isOn: $muted)
                Stepper("Position Precision: \(precision)", value: $precision, in: 0...32)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            }
            .navigationTitle("Channel \(channel.index)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        guard name.utf8.count <= 11 else {
                            errorMessage = "Channel names must be 11 bytes or fewer"
                            return
                        }
                        guard let decodedKey = Data(base64Encoded: key), [0, 1, 16, 32].contains(decodedKey.count) else {
                            errorMessage = "Key must be valid base64 with 0, 1, 16, or 32 bytes"
                            return
                        }
                        var edited = channel
                        edited.settings.name = name
                        edited.settings.psk = decodedKey
                        edited.role = role
                        edited.settings.uplinkEnabled = uplink
                        edited.settings.downlinkEnabled = downlink
                        edited.settings.moduleSettings.positionPrecision = UInt32(precision)
                        edited.settings.moduleSettings.isMuted = muted
                        Task {
                            do { try await onSave(edited) }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
