//
//  RemoteShellLink.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
import MeshtasticProtobufs

/// The client side of the remote shell protocol (firmware's DMShell module, 2.8.2), with no
/// radio or timers of its own: the session feeds it frames and clock ticks and sends what it
/// queues in `outbox`.
///
/// Each direction numbers its frames from 1. Every sequenced frame carries `ack_seq`, the
/// highest frame received in order. At most four frames are unacknowledged each way; when the
/// window is full the oldest is resent. A bare ACK (`seq` 0) with `last_rx_seq` above 0 asks
/// the other side to resend from the frame after it, so plain ACKs leave it at 0. The rules
/// and limits follow the firmware's reference client and the Android app.
struct RemoteShellLink {

	enum Phase: Equatable {
		case idle, opening, open, closed
	}

	enum Failure: Equatable {
		/// The node never answered the OPEN.
		case noReply
		/// The node stopped acknowledging frames.
		case stoppedAnswering
		/// The node asked for input that has already left the resend history.
		case replayEvicted
		/// The node said there is no session, with its reason.
		case refused(String)
	}

	enum Event: Equatable {
		case opened(cols: UInt32, rows: UInt32)
		case output(Data)
		/// The node closed the session, with its reason.
		case closed(reason: String)
		case failed(Failure)
		/// An error the node reported while the session stays up.
		case nodeError(String)
		/// Input that didn't fit in the queue.
		case inputDropped(Int)
	}

	static let window: UInt32 = 4
	static let historyLimit = 50
	static let heldLimit = 8
	static let maxPayload = 200
	static let maxQueuedInput = 4_096
	static let openGiveUp: TimeInterval = 60
	static let maxRetransmits = 25
	static let pingAfterSilence: TimeInterval = 5
	static let pingInterval: TimeInterval = 15

	let sessionId: UInt32
	private(set) var phase = Phase.idle
	/// Smoothed round trip, once a frame has been acknowledged.
	private(set) var roundTrip: TimeInterval?
	private(set) var lastReceivedAt: Date?

	/// Frames to send, oldest first. The session drains it.
	var outbox: [RemoteShell] = []
	/// What happened, oldest first. The session drains it.
	var events: [Event] = []

	private struct Sent {
		var frame: RemoteShell
		let firstSentAt: Date
		var lastSentAt: Date
		var resent = false
	}

	private var nextTxSeq: UInt32 = 1
	private var history: [UInt32: Sent] = [:]
	/// Our highest sent frame the node has acknowledged.
	private var peerCursor: UInt32 = 0
	private var highestSent: UInt32 = 0
	/// The highest frame received in order.
	private var lastRxSeq: UInt32 = 0
	private var held: [UInt32: RemoteShell] = [:]
	private var inOrderSinceAck = 0
	private var retransmits = 0
	private var gapRetries = 0
	private var nextGapRequest: Date?
	private var openSentAt: Date?
	private var openWait: TimeInterval = 5
	private var nextOpenRetry: Date?
	private var lastPingAt: Date?
	private var queuedInput = Data()
	private var pendingResize: (cols: UInt32, rows: UInt32)?

	init(sessionId: UInt32 = UInt32.random(in: 1...0x7FFF_FFFF)) {
		self.sessionId = sessionId
	}

	// MARK: - Commands

	mutating func open(cols: UInt32, rows: UInt32, now: Date) {
		guard phase == .idle else { return }
		phase = .opening
		var frame = RemoteShell()
		frame.op = .open
		frame.cols = cols
		frame.rows = rows
		sendSequenced(frame, now: now)
		openSentAt = now
		openWait = 5
		nextOpenRetry = now.addingTimeInterval(openWait)
	}

	mutating func send(_ input: Data, now: Date) {
		guard phase == .opening || phase == .open, !input.isEmpty else { return }
		let room = Self.maxQueuedInput - queuedInput.count
		if input.count > room {
			queuedInput.append(input.prefix(room))
			events.append(.inputDropped(input.count - room))
		} else {
			queuedInput.append(input)
		}
		pump(now: now)
	}

	mutating func resize(cols: UInt32, rows: UInt32, now: Date) {
		guard phase == .opening || phase == .open, cols > 0, rows > 0 else { return }
		pendingResize = (cols, rows)
		pump(now: now)
	}

	/// Ends the session from this side.
	mutating func close() {
		guard phase == .opening || phase == .open else { return }
		sendClose()
		phase = .closed
	}

	// MARK: - Receiving

	mutating func receive(_ frame: RemoteShell, now: Date) {
		guard frame.sessionID == sessionId, phase == .opening || phase == .open else { return }
		lastReceivedAt = now
		advancePeerCursor(to: max(frame.ackSeq, frame.lastRxSeq), now: now)

		switch frame.op {
		case .closed:
			// Terminal, even out of order.
			finish(.closed(reason: Self.text(frame.payload)), sendClose: false)
			return
		case .ack where frame.seq == 0:
			if frame.lastRxSeq > 0 {
				replay(from: frame.lastRxSeq + 1, now: now)
			}
			pump(now: now)
			return
		case .error where frame.seq == 0:
			finish(.failed(.refused(Self.text(frame.payload))), sendClose: false)
			return
		default:
			break
		}
		guard frame.seq > 0 else { return }

		if frame.seq <= lastRxSeq {
			sendAck(now: now)
			return
		}
		if frame.seq != lastRxSeq + 1 {
			hold(frame)
			requestGap(now: now)
			return
		}
		process(frame, now: now)
		while phase != .closed, let next = held.removeValue(forKey: lastRxSeq + 1) {
			process(next, now: now)
		}
		if held.isEmpty {
			nextGapRequest = nil
			gapRetries = 0
		}
		if inOrderSinceAck >= 2 {
			sendAck(now: now)
		}
		pump(now: now)
	}

	private mutating func process(_ frame: RemoteShell, now: Date) {
		lastRxSeq = frame.seq
		inOrderSinceAck += 1
		switch frame.op {
		case .openOk:
			guard phase == .opening else { return }
			phase = .open
			nextOpenRetry = nil
			events.append(.opened(cols: frame.cols, rows: frame.rows))
		case .output:
			if !frame.payload.isEmpty {
				events.append(.output(frame.payload))
			}
		case .pong:
			if frame.lastRxSeq < highestSent {
				replay(from: frame.lastRxSeq + 1, now: now)
			}
			if frame.lastTxSeq > lastRxSeq {
				requestGap(now: now)
			}
		case .error:
			events.append(.nodeError(Self.text(frame.payload)))
		default:
			break
		}
	}

	private mutating func hold(_ frame: RemoteShell) {
		guard held[frame.seq] == nil else { return }
		if held.count >= Self.heldLimit {
			guard let highest = held.keys.max(), frame.seq < highest else { return }
			held.removeValue(forKey: highest)
		}
		held[frame.seq] = frame
	}

	/// A reason or message the node sent as text.
	private static func text(_ payload: Data) -> String {
		String(data: payload, encoding: .utf8) ?? ""
	}

	// MARK: - Clock

	mutating func tick(now: Date) {
		switch phase {
		case .opening:
			guard let openSentAt, let nextOpenRetry, now >= nextOpenRetry else { break }
			if now.timeIntervalSince(openSentAt) >= Self.openGiveUp {
				finish(.failed(.noReply), sendClose: true)
				return
			}
			if var open = history[1] {
				outbox.append(open.frame)
				open.lastSentAt = now
				open.resent = true
				history[1] = open
			}
			openWait = min(openWait * 2, 30)
			self.nextOpenRetry = now.addingTimeInterval(openWait)
		case .open:
			retransmitIfStalled(now: now)
			guard phase == .open else { return }
			if !held.isEmpty, let nextGapRequest, now >= nextGapRequest {
				requestGap(now: now, force: true)
			}
			let silence = now.timeIntervalSince(lastReceivedAt ?? openSentAt ?? now)
			let sincePing = lastPingAt.map { now.timeIntervalSince($0) } ?? .infinity
			if silence >= Self.pingAfterSilence, sincePing >= Self.pingInterval {
				var ping = RemoteShell()
				ping.op = .ping
				ping.lastTxSeq = highestSent
				ping.lastRxSeq = lastRxSeq
				sendSequenced(ping, now: now)
				lastPingAt = now
			}
			pump(now: now)
		case .idle, .closed:
			break
		}
	}

	/// How long the oldest unacknowledged frame has waited, or nil when nothing is outstanding.
	func oldestUnackedAge(now: Date) -> TimeInterval? {
		guard peerCursor < highestSent, let oldest = history[peerCursor + 1] else { return nil }
		return now.timeIntervalSince(oldest.firstSentAt)
	}

	private mutating func retransmitIfStalled(now: Date) {
		guard highestSent - peerCursor >= Self.window, var oldest = history[peerCursor + 1] else { return }
		let base = min(max(2 * (roundTrip ?? 1), 1), 8)
		let wait = retransmits < 4 ? base : min(base * pow(2, Double(retransmits - 3)), 8)
		guard now.timeIntervalSince(oldest.lastSentAt) >= wait else { return }
		retransmits += 1
		if retransmits > Self.maxRetransmits {
			finish(.failed(.stoppedAnswering), sendClose: true)
			return
		}
		oldest.frame.ackSeq = lastRxSeq
		oldest.lastSentAt = now
		oldest.resent = true
		history[peerCursor + 1] = oldest
		outbox.append(oldest.frame)
	}

	// MARK: - Sending

	private var windowHasRoom: Bool {
		highestSent - peerCursor < Self.window
	}

	private mutating func pump(now: Date) {
		guard phase == .open else { return }
		if let resize = pendingResize, windowHasRoom {
			var frame = RemoteShell()
			frame.op = .resize
			frame.cols = resize.cols
			frame.rows = resize.rows
			sendSequenced(frame, now: now)
			pendingResize = nil
		}
		while !queuedInput.isEmpty, windowHasRoom {
			var frame = RemoteShell()
			frame.op = .input
			frame.payload = Data(queuedInput.prefix(Self.maxPayload))
			queuedInput.removeFirst(frame.payload.count)
			sendSequenced(frame, now: now)
		}
	}

	private mutating func sendSequenced(_ frame: RemoteShell, now: Date) {
		var frame = frame
		frame.sessionID = sessionId
		frame.seq = nextTxSeq
		frame.ackSeq = lastRxSeq
		nextTxSeq += 1
		highestSent = frame.seq
		inOrderSinceAck = 0
		history[frame.seq] = Sent(frame: frame, firstSentAt: now, lastSentAt: now)
		if history.count > Self.historyLimit, let oldest = history.keys.min() {
			history.removeValue(forKey: oldest)
		}
		outbox.append(frame)
	}

	private mutating func sendAck(now: Date) {
		var ack = RemoteShell()
		ack.op = .ack
		ack.sessionID = sessionId
		ack.ackSeq = lastRxSeq
		inOrderSinceAck = 0
		outbox.append(ack)
	}

	/// Asks the node to resend from the first frame missing here.
	private mutating func requestGap(now: Date, force: Bool = false) {
		if !force, let nextGapRequest, now < nextGapRequest { return }
		var ack = RemoteShell()
		ack.op = .ack
		ack.sessionID = sessionId
		ack.ackSeq = lastRxSeq
		ack.lastRxSeq = lastRxSeq
		inOrderSinceAck = 0
		outbox.append(ack)
		let base = min(max(2 * (roundTrip ?? 1), 1), 8)
		let wait = gapRetries < 4 ? base : min(base * pow(2, Double(gapRetries - 3)), 8)
		gapRetries += 1
		nextGapRequest = now.addingTimeInterval(wait)
	}

	private mutating func replay(from seq: UInt32, now: Date) {
		guard seq <= highestSent else { return }
		for number in seq...highestSent {
			guard var sent = history[number] else {
				finish(.failed(.replayEvicted), sendClose: true)
				return
			}
			sent.frame.ackSeq = lastRxSeq
			sent.lastSentAt = now
			sent.resent = true
			history[number] = sent
			outbox.append(sent.frame)
		}
	}

	private mutating func sendClose() {
		var close = RemoteShell()
		close.op = .close
		close.sessionID = sessionId
		close.ackSeq = lastRxSeq
		outbox.append(close)
	}

	private mutating func finish(_ event: Event, sendClose: Bool) {
		if sendClose { self.sendClose() }
		phase = .closed
		events.append(event)
	}

	private mutating func advancePeerCursor(to acknowledged: UInt32, now: Date) {
		let cursor = min(acknowledged, highestSent)
		guard cursor > peerCursor else { return }
		if let newest = history[cursor], !newest.resent {
			let sample = now.timeIntervalSince(newest.firstSentAt)
			roundTrip = roundTrip.map { $0 + 0.25 * (sample - $0) } ?? sample
		}
		peerCursor = cursor
		retransmits = 0
	}
}
