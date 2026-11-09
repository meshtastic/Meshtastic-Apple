//
//  RemoteShellSession.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
import MeshtasticProtobufs
import OSLog
@preconcurrency import SwiftData

/// A sticky modifier on the extra key rows: one tap applies it to the next key, a second locks
/// it, a third releases it.
enum StickyModifier: Equatable {
	case off, once, locked

	var next: StickyModifier {
		switch self {
		case .off: .once
		case .once: .locked
		case .locked: .off
		}
	}
}

/// Keys the on-screen rows and a hardware keyboard send that have no character of their own.
enum TerminalKey: Equatable {
	case escape, tab, up, down, left, right, home, end, pageUp, pageDown, delete

	func bytes(applicationCursor: Bool) -> [UInt8] {
		let lead: [UInt8] = applicationCursor ? [0x1B, 0x4F] : [0x1B, 0x5B]
		switch self {
		case .escape: return [0x1B]
		case .tab: return [0x09]
		case .up: return lead + [0x41]
		case .down: return lead + [0x42]
		case .right: return lead + [0x43]
		case .left: return lead + [0x44]
		case .home: return lead + [0x48]
		case .end: return lead + [0x46]
		case .pageUp: return Array("\u{1B}[5~".utf8)
		case .pageDown: return Array("\u{1B}[6~".utf8)
		case .delete: return Array("\u{1B}[3~".utf8)
		}
	}
}

/// One remote shell on one node: sets up the remote admin session, runs the protocol, keeps
/// the screen, and turns key presses into input.
@MainActor
final class RemoteShellSession: ObservableObject {

	enum State: Equatable {
		case startingAdmin
		case opening
		case open
		case closing
		/// Closed by the node, with its reason, or by this side.
		case closed(reason: String?)
		case failed(String)

		var canReconnect: Bool {
			switch self {
			case .closed, .failed: true
			default: false
			}
		}
	}

	/// The session frames are routed to. One at a time, like the node allows.
	private(set) static weak var active: RemoteShellSession?

	/// How long to wait for the node to answer the remote admin request.
	static let adminTimeout: TimeInterval = 30
	/// When an unacknowledged frame has waited this long, the waiting notice shows.
	static let waitingAfter: TimeInterval = 4
	private static let tickInterval: Duration = .milliseconds(250)
	private static let keyBatchIdle: TimeInterval = 0.5
	private static let keyBatchMaxHold: TimeInterval = 2
	private static let keyBatchMaxBytes = 64

	let nodeNum: Int64
	let nodeName: String

	@Published private(set) var state = State.startingAdmin
	@Published private(set) var screen = TerminalScreen()
	@Published private(set) var echo = LocalEcho()
	/// Characters typed but held back to batch them into one frame.
	@Published private(set) var pendingText = ""
	@Published private(set) var roundTrip: TimeInterval?
	/// Seconds since the node was last heard, while a frame is waiting on it.
	@Published private(set) var waitingLastHeard: Int?
	/// A message from the node or about dropped input, shown above the terminal.
	@Published var notice: String?
	@Published var control = StickyModifier.off
	@Published var alt = StickyModifier.off

	private let accessoryManager: AccessoryManager
	private var link = RemoteShellLink()
	private var size: (cols: UInt32, rows: UInt32)?
	private var publicKey = Data()
	private var tickTask: Task<Void, Never>?
	private var startTask: Task<Void, Never>?
	private var pendingSince: Date?
	private var lastKeyAt: Date?
	private var lastBellCount = 0
	private var sendQueue: [RemoteShell] = []
	private var isSending = false

	init(nodeNum: Int64, nodeName: String, accessoryManager: AccessoryManager) {
		self.nodeNum = nodeNum
		self.nodeName = nodeName
		self.accessoryManager = accessoryManager
	}

	/// Whether the line the cursor is on asks for a password, passphrase or PIN.
	var atSecretPrompt: Bool {
		LocalEcho.isSecretPrompt(screen.currentLineText)
	}

	// MARK: - Lifecycle

	func start() {
		guard startTask == nil else { return }
		Self.active = self
		link = RemoteShellLink()
		echo = LocalEcho()
		pendingText = ""
		roundTrip = nil
		waitingLastHeard = nil
		state = .startingAdmin
		startTask = Task { [weak self] in
			await self?.establishAdminSession()
		}
		tickTask?.cancel()
		tickTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: Self.tickInterval)
				self?.tick()
			}
		}
	}

	func reconnect() {
		guard state.canReconnect else { return }
		startTask = nil
		start()
	}

	/// Ends the session. It shows as closing until the CLOSE frame has gone to the radio, then
	/// closed (design#163 requirement 4). Calling it again, as leaving the screen does, is a no-op.
	func close() {
		startTask?.cancel()
		tickTask?.cancel()
		tickTask = nil
		if Self.active === self {
			Self.active = nil
		}
		guard link.phase == .opening || link.phase == .open else {
			if state != .closing, !state.canReconnect {
				state = .closed(reason: nil)
			}
			return
		}
		link.close()
		state = .closing
		drain()
		finishClosingIfSent()
	}

	private func finishClosingIfSent() {
		if state == .closing, !isSending, sendQueue.isEmpty {
			state = .closed(reason: nil)
		}
	}

	/// The terminal's size in characters, from the view. Opens the session the first time.
	func setTerminalSize(cols: Int, rows: Int) {
		let new = (UInt32(max(cols, 10)), UInt32(max(rows, 4)))
		if let size, size == new { return }
		size = new
		switch link.phase {
		case .idle:
			openIfReady()
		case .opening, .open:
			link.resize(cols: new.0, rows: new.1, now: .now)
			drain()
		case .closed:
			break
		}
	}

	private func establishAdminSession() async {
		guard let node = fetchNode(), let toUser = node.user else {
			state = .failed(String(localized: "This node isn't in the node list."))
			return
		}
		guard let key = toUser.publicKey, key.count == 32 else {
			state = .failed(String(localized: "This node hasn't shared a public key yet, so a remote shell can't be opened to it."))
			return
		}
		publicKey = key
		if !Self.adminSessionIsActive(node) {
			guard let fromUser = accessoryManager.activeDeviceNum.flatMap({ fetchNode($0)?.user }) else {
				state = .failed(String(localized: "Connect to your radio to open a remote shell."))
				return
			}
			do {
				_ = try await accessoryManager.requestDeviceMetadata(fromUser: fromUser, toUser: toUser)
			} catch {
				state = .failed(String(localized: "Connect to your radio to open a remote shell."))
				return
			}
			let deadline = Date.now.addingTimeInterval(Self.adminTimeout)
			while Date.now < deadline {
				try? await Task.sleep(for: .milliseconds(500))
				if Task.isCancelled { return }
				if let node = fetchNode(), Self.adminSessionIsActive(node) { break }
			}
			guard let node = fetchNode(), Self.adminSessionIsActive(node) else {
				state = .failed(Self.noReplyMessage)
				return
			}
		}
		if let node = fetchNode(), !node.firmwareSupportsRemoteShell {
			state = .failed(String(localized: "This node's firmware is older than 2.8.2, which added the remote shell. Update it to use the shell."))
			return
		}
		state = .opening
		openIfReady()
	}

	private func openIfReady() {
		guard state == .opening, link.phase == .idle, let size else { return }
		link.open(cols: size.cols, rows: size.rows, now: .now)
		drain()
	}

	static func adminSessionIsActive(_ node: NodeInfoEntity) -> Bool {
		guard let passkey = node.sessionPasskey, !passkey.isEmpty,
			  let expiration = node.sessionExpiration else { return false }
		return expiration > .now
	}

	static let noReplyMessage = String(localized: "No reply from the node. It must list your radio's public key as an admin key, and be in range.")

	private func fetchNode(_ num: Int64? = nil) -> NodeInfoEntity? {
		let num = num ?? nodeNum
		let context = ModelContext(PersistenceController.shared.container)
		var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		descriptor.fetchLimit = 1
		return try? context.fetch(descriptor).first
	}

	// MARK: - Receiving

	/// Routes a remote shell packet to the open session for its node.
	static func deliver(_ packet: MeshPacket) {
		guard let session = active, Int64(packet.from) == session.nodeNum,
			  let frame = try? RemoteShell(serializedBytes: packet.decoded.payload) else { return }
		session.link.receive(frame, now: .now)
		session.drain()
	}

	/// A routing error from the node: a refused session comes back as NOT_AUTHORIZED.
	static func deliverRouting(_ packet: MeshPacket) {
		guard let session = active, Int64(packet.from) == session.nodeNum,
			  session.link.phase == .opening || session.link.phase == .open,
			  let routing = try? Routing(serializedBytes: packet.decoded.payload),
			  routing.errorReason == .notAuthorized else { return }
		session.link.close()
		session.drain()
		session.state = .failed(String(localized: "The node refused the session. It must list your radio's public key as an admin key."))
	}

	private func drain() {
		let frames = link.outbox
		link.outbox = []
		sendQueue.append(contentsOf: frames)
		flushSendQueue()

		let events = link.events
		link.events = []
		for event in events {
			handle(event)
		}
		roundTrip = link.roundTrip
	}

	/// Sends frames one at a time, in order.
	private func flushSendQueue() {
		guard !isSending, !sendQueue.isEmpty else { return }
		isSending = true
		let frame = sendQueue.removeFirst()
		// Holds the session until the queue drains, so a CLOSE queued as the view goes away is
		// still sent. Each task lives for one send.
		Task { [self, nodeNum, publicKey, accessoryManager] in
			do {
				try await accessoryManager.sendRemoteShell(frame, to: nodeNum, publicKey: publicKey)
			} catch {
				Logger.mesh.error("💻 [Remote Shell] Send failed: \(error.localizedDescription, privacy: .public)")
				// The node never heard the session end, so don't report it closed.
				if state == .closing {
					sendQueue.removeAll()
					state = .failed(String(localized: "Couldn't tell the node to end the session: \(error.localizedDescription)"))
				}
			}
			isSending = false
			flushSendQueue()
			finishClosingIfSent()
		}
	}

	private func handle(_ event: RemoteShellLink.Event) {
		switch event {
		case .opened:
			state = .open
			Logger.mesh.info("💻 [Remote Shell] Session open on \(self.nodeNum.toHex(), privacy: .public)")
		case let .output(data):
			echo.received(data)
			screen.feed(data)
			if screen.bellCount != lastBellCount {
				lastBellCount = screen.bellCount
				Haptics.impact(.light)
			}
		case let .closed(reason):
			state = .closed(reason: reason.isEmpty ? nil : reason)
		case let .failed(failure):
			switch failure {
			case .noReply:
				state = .failed(Self.noReplyMessage)
			case .stoppedAnswering:
				state = .failed(String(localized: "The node stopped answering."))
			case .replayEvicted:
				state = .failed(String(localized: "The node asked for input this device no longer holds."))
			case let .refused(reason):
				state = .failed(String(localized: "Could not open the session (\(reason)). The node must list your radio's public key as an admin key, and be in range."))
			}
		case let .nodeError(message):
			notice = String(localized: "Error from the node: \(message)")
		case let .inputDropped(count):
			notice = String(localized: "\(count) bytes of input dropped, the node is not keeping up")
		}
	}

	// MARK: - Clock

	private func tick() {
		let now = Date.now
		link.tick(now: now)
		echo.expire(now: now, roundTrip: link.roundTrip)
		if let pendingSince, let lastKeyAt,
		   now.timeIntervalSince(lastKeyAt) >= Self.keyBatchIdle || now.timeIntervalSince(pendingSince) >= Self.keyBatchMaxHold {
			flushPendingText()
		}
		drain()
		if let age = link.oldestUnackedAge(now: now), age >= Self.waitingAfter {
			let heard = link.lastReceivedAt.map { Int(now.timeIntervalSince($0)) } ?? Int(age)
			if waitingLastHeard != heard { waitingLastHeard = heard }
		} else if waitingLastHeard != nil {
			waitingLastHeard = nil
		}
	}

	// MARK: - Input

	/// Text from the keyboard or a paste. In character mode printable characters are batched
	/// and predicted; a newline is Enter.
	func type(_ text: String) {
		for character in text {
			if character == "\n" || character == "\r" {
				enter()
			} else if control != .off || alt != .off {
				sendModified(character)
			} else if let ascii = character.asciiValue, ascii < 0x20 || ascii == 0x7F {
				sendNow([ascii])
				echo.control()
			} else {
				pendingText.append(character)
				echo.typed(character)
				let now = Date.now
				if pendingSince == nil { pendingSince = now }
				lastKeyAt = now
				if pendingText.utf8.count >= Self.keyBatchMaxBytes {
					flushPendingText()
				}
			}
		}
	}

	func enter() {
		flushPendingText()
		echo.enter()
		sendNow([0x0D])
	}

	/// Backspace edits held-back text first, and only reaches the node once there is none.
	func backspace() {
		if !pendingText.isEmpty {
			pendingText.removeLast()
			echo.removeUnsent()
			if pendingText.isEmpty {
				pendingSince = nil
			}
			return
		}
		echo.backspace()
		sendNow([0x7F])
	}

	func send(_ key: TerminalKey) {
		var bytes = key.bytes(applicationCursor: screen.applicationCursorKeys)
		if alt != .off, key != .escape {
			bytes.insert(0x1B, at: 0)
		}
		releaseOnceModifiers()
		echo.control()
		sendNow(bytes)
	}

	/// A key chord from a hardware keyboard.
	func sendChord(_ character: Character, control: Bool, alt: Bool) {
		guard let bytes = Self.chordBytes(character, control: control, alt: alt) else { return }
		echo.control()
		sendNow(bytes)
	}

	/// Pasted text goes out as is, with line endings as Enter.
	func paste(_ text: String) {
		let normalized = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
		echo.control()
		sendNow(Array(normalized.utf8))
	}

	/// A whole command from line mode, in one frame.
	func sendLine(_ line: String) {
		echo.enter()
		sendNow(Array((line + "\r").utf8))
	}

	func clearScreen() {
		screen.clear()
	}

	func acknowledgeFullScreen() {
		screen.acknowledgeFullScreen()
	}

	private func sendModified(_ character: Character) {
		let bytes = Self.chordBytes(character, control: control != .off, alt: alt != .off)
		releaseOnceModifiers()
		echo.control()
		if let bytes { sendNow(bytes) }
	}

	private func releaseOnceModifiers() {
		if control == .once { control = .off }
		if alt == .once { alt = .off }
	}

	nonisolated static func chordBytes(_ character: Character, control: Bool, alt: Bool) -> [UInt8]? {
		var bytes = Array(String(character).utf8)
		if control {
			guard let ascii = character.asciiValue else { return nil }
			switch ascii {
			case 0x20: bytes = [0x00]
			case 0x3F: bytes = [0x7F]
			case 0x40...0x5F, 0x61...0x7A: bytes = [Character(Unicode.Scalar(ascii)).uppercased().utf8.first! & 0x1F]
			default: break
			}
		}
		if alt {
			bytes.insert(0x1B, at: 0)
		}
		return bytes
	}

	private func flushPendingText() {
		pendingSince = nil
		lastKeyAt = nil
		guard !pendingText.isEmpty else { return }
		let bytes = Data(pendingText.utf8)
		pendingText = ""
		echo.markSent(now: .now)
		link.send(bytes, now: .now)
		drain()
	}

	private func sendNow(_ bytes: [UInt8]) {
		flushPendingText()
		link.send(Data(bytes), now: .now)
		drain()
	}
}

extension NodeInfoEntity {
	/// Whether this node runs `meshtasticd` on Linux, where the remote shell lives.
	var isLinuxNative: Bool {
		user?.hwModel == "PORTDUINO"
	}

	/// The remote shell module arrived in 2.8.2. Permissive when the version isn't known yet;
	/// opening the shell fetches it.
	var firmwareSupportsRemoteShell: Bool { firmwareAtLeast("2.8.2") }
}

extension AccessoryManager {
	/// Sends one remote shell frame as a PKI direct message. The protocol has its own
	/// acknowledgements, so the mesh's are off.
	func sendRemoteShell(_ frame: RemoteShell, to nodeNum: Int64, publicKey: Data) async throws {
		var packet = MeshPacket()
		packet.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		packet.to = UInt32(nodeNum)
		packet.from = UInt32(activeDeviceNum ?? 0)
		packet.wantAck = false
		packet.pkiEncrypted = true
		packet.publicKey = publicKey
		var data = DataMessage()
		data.portnum = .remoteShellApp
		data.payload = try frame.serializedData()
		packet.decoded = data
		var toRadio = ToRadio()
		toRadio.packet = packet
		try await send(toRadio)
	}
}
