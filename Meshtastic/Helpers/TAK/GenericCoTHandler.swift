//
//  GenericCoTHandler.swift
//  Meshtastic
//
//  Handles generic CoT events that don't map to TAKPacket protobuf
//  Uses EXI compression and Fountain codes for reliable transfer
//

import Foundation
import MeshtasticProtobufs
import OSLog

/// Port numbers for TAK communication
enum TAKPortNum: UInt32 {
	/// TAKPacket protobuf (PLI, GeoChat) - small, structured messages
	case atakPlugin = 72

	/// EXI-compressed CoT XML - generic/large messages, fountain coded
	case atakForwarder = 257
}

/// Handler for generic CoT events over the mesh network
@MainActor
final class GenericCoTHandler {

	static let shared = GenericCoTHandler()

	weak var accessoryManager: AccessoryManager?

	/// Pending outgoing fountain transfers awaiting ACK
	private var pendingTransfers: [UInt32: PendingTransfer] = [:]

	private init() {}

	// MARK: - Outgoing CoT Classification

	/// Determine how a CoT message should be sent
	enum CoTSendMethod {
		/// Use TAKPacket.pli on ATAK_PLUGIN port
		case takPacketPLI
		/// Use TAKPacket.chat on ATAK_PLUGIN port
		case takPacketChat
		/// Use EXI compression on ATAK_FORWARDER port (small, no fountain)
		case exiDirect
		/// Use EXI + Fountain coding on ATAK_FORWARDER port (large)
		case exiFountain
	}

	/// Classify a CoT message to determine send method
	func classifySendMethod(for cot: CoTMessage) -> CoTSendMethod {
		// Self PLI (position)
		if cot.type.hasPrefix("a-f-G") || cot.type.hasPrefix("a-f-g") {
			return .takPacketPLI
		}

		// GeoChat
		if cot.type == "b-t-f" {
			return .takPacketChat
		}

		// Everything else goes through EXI/Forwarder
		// Check compressed size to determine if fountain coding needed
		let xml = cot.toXML()
		if let compressed = EXICodec.shared.compress(xml) {
			// +1 for transfer type byte
			if compressed.count + 1 < FountainConstants.fountainThreshold {
				return .exiDirect
			} else {
				return .exiFountain
			}
		}

		// Fallback to direct (compression failed, use raw)
		return .exiDirect
	}

	// MARK: - Sending Generic CoT

	/// Send a generic CoT event (markers, shapes, routes, etc.)
	/// - Parameters:
	///   - cot: The CoT message to send
	///   - channel: Meshtastic channel (0 = primary)
	func sendGenericCoT(_ cot: CoTMessage, channel: UInt32 = 0) async throws {
		guard let accessoryManager else {
			throw GenericCoTError.notConnected
		}

		guard accessoryManager.isConnected else {
			throw GenericCoTError.notConnected
		}

		// Compress to EXI
		let xml = cot.toXML()
		guard let exiData = EXICodec.shared.compress(xml) else {
			throw GenericCoTError.compressionFailed
		}

		// Prepend transfer type
		var payload = Data([FountainConstants.transferTypeCot])
		payload.append(exiData)

		Logger.tak.debug("Generic CoT: type=\(cot.type), xml=\(xml.count)B, compressed=\(payload.count)B")

		// Check if small enough to send directly
		if payload.count < FountainConstants.fountainThreshold {
			try await sendDirect(payload, channel: channel)
		} else {
			try await sendFountainCoded(payload, channel: channel)
		}
	}

	/// Send small payload directly (no fountain coding)
	private func sendDirect(_ payload: Data, channel: UInt32) async throws {
		guard let accessoryManager, let activeConnection = accessoryManager.activeConnection else {
			throw GenericCoTError.notConnected
		}

		guard let deviceNum = activeConnection.device.num else {
			throw GenericCoTError.noDeviceNumber
		}

		var dataMessage = DataMessage()
		dataMessage.portnum = .atakForwarder  // Port 257
		dataMessage.payload = payload

		var meshPacket = MeshPacket()
		meshPacket.to = 0xFFFFFFFF  // Broadcast
		meshPacket.from = UInt32(deviceNum)
		meshPacket.channel = channel
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.decoded = dataMessage

		var toRadio = ToRadio()
		toRadio.packet = meshPacket

		try await accessoryManager.send(toRadio, debugDescription: "Generic CoT (direct)")

		Logger.tak.info("Sent generic CoT directly: \(payload.count) bytes on port 257")
	}

	/// Send large payload using fountain coding
	private func sendFountainCoded(_ payload: Data, channel: UInt32) async throws {
		guard let accessoryManager, let activeConnection = accessoryManager.activeConnection else {
			throw GenericCoTError.notConnected
		}

		guard let deviceNum = activeConnection.device.num else {
			throw GenericCoTError.noDeviceNumber
		}

		let transferId = FountainCodec.shared.generateTransferId()
		let packets = FountainCodec.shared.encode(data: payload, transferId: transferId)

		Logger.tak.info("Sending fountain-coded CoT: \(payload.count) bytes → \(packets.count) blocks, xferId=\(transferId)")

		// Track pending transfer
		pendingTransfers[transferId] = PendingTransfer(
			transferId: transferId,
			totalBlocks: packets.count,
			dataHash: FountainCodec.computeHash(payload)
		)

		// Send all blocks with inter-packet delay
		for (index, packetData) in packets.enumerated() {
			var dataMessage = DataMessage()
			dataMessage.portnum = .atakForwarder
			dataMessage.payload = packetData

			var meshPacket = MeshPacket()
			meshPacket.to = 0xFFFFFFFF
			meshPacket.from = UInt32(deviceNum)
			meshPacket.channel = channel
			meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
			meshPacket.decoded = dataMessage

			var toRadio = ToRadio()
			toRadio.packet = meshPacket

			try await accessoryManager.send(toRadio, debugDescription: "Fountain block \(index + 1)/\(packets.count)")

			// Inter-packet delay (100ms default, could be adjusted based on modem preset)
			if index < packets.count - 1 {
				try await Task.sleep(nanoseconds: 100_000_000)
			}
		}

		Logger.tak.info("Fountain transfer \(transferId) complete: sent \(packets.count) blocks")
	}

	// MARK: - Receiving Generic CoT

	/// Handle incoming ATAK_FORWARDER packet (port 257)
	/// - Parameters:
	///   - packet: The mesh packet
	/// - Returns: Decoded CoT message if successful
	func handleIncomingForwarderPacket(_ packet: MeshPacket) -> CoTMessage? {
		guard case let .decoded(data) = packet.payloadVariant else {
			Logger.tak.warning("ATAK_FORWARDER packet without decoded payload")
			return nil
		}

		let payload = data.payload
		guard !payload.isEmpty else {
			Logger.tak.warning("Empty ATAK_FORWARDER payload")
			return nil
		}

		// Check if this is a fountain packet (starts with "FTN" magic)
		if FountainCodec.isFountainPacket(payload) {
			// Distinguish between ACK (19 bytes) and data block (231 bytes)
			// ACK: magic(3) + transferId(3) + type(1) + received(2) + needed(2) + hash(8) = 19
			// Data: magic(3) + transferId(3) + seed(2) + K(1) + totalLen(2) + payload(220) = 231
			if payload.count == FountainConstants.ackPacketSize {
				// This is a fountain ACK - handle it and return nil (no CoT to forward)
				handleIncomingAck(payload, from: packet.from)
				return nil
			}
			return handleFountainPacket(payload, from: packet.from)
		}

		// Direct packet (not fountain coded)
		return handleDirectPacket(payload, from: packet.from)
	}

	/// Handle direct (non-fountain) packet
	private func handleDirectPacket(_ payload: Data, from nodeNum: UInt32) -> CoTMessage? {
		guard payload.count > 1 else {
			Logger.tak.warning("Direct packet too short: \(payload.count) bytes")
			return nil
		}

		let transferType = payload[0]
		let exiData = payload.dropFirst()

		guard transferType == FountainConstants.transferTypeCot else {
			Logger.tak.debug("Ignoring non-CoT transfer type: \(transferType)")
			return nil
		}

		// Decompress EXI to XML
		guard let xml = EXICodec.shared.decompress(Data(exiData)) else {
			Logger.tak.warning("Failed to decompress EXI data from node \(nodeNum)")
			return nil
		}

		// Parse CoT XML
		guard let cot = CoTMessage.parse(from: xml) else {
			Logger.tak.warning("Failed to parse CoT XML from node \(nodeNum)")
			return nil
		}

		Logger.tak.info("Received generic CoT from node \(nodeNum): \(cot.type)")
		return cot
	}

	/// Handle fountain-coded packet
	private func handleFountainPacket(_ payload: Data, from nodeNum: UInt32) -> CoTMessage? {
		// Pass to fountain codec
		guard let (decodedData, transferId) = FountainCodec.shared.handleIncomingPacket(payload, senderNodeId: nodeNum) else {
			// Not yet complete, waiting for more blocks
			return nil
		}

		// Transfer complete - send ACK (twice for redundancy)
		let hash = FountainCodec.computeHash(decodedData)
		Task {
			await sendFountainAck(transferId: transferId, hash: hash, to: nodeNum)
			try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms delay
			await sendFountainAck(transferId: transferId, hash: hash, to: nodeNum)
		}

		// Extract transfer type and data
		guard decodedData.count > 1 else {
			Logger.tak.warning("Decoded fountain data too short")
			return nil
		}

		let transferType = decodedData[0]
		let exiData = decodedData.dropFirst()

		guard transferType == FountainConstants.transferTypeCot else {
			Logger.tak.debug("Ignoring non-CoT fountain transfer type: \(transferType)")
			return nil
		}

		// Decompress EXI to XML
		guard let xml = EXICodec.shared.decompress(Data(exiData)) else {
			Logger.tak.warning("Failed to decompress fountain EXI data")
			return nil
		}

		// Parse CoT XML
		guard let cot = CoTMessage.parse(from: xml) else {
			Logger.tak.warning("Failed to parse fountain CoT XML")
			return nil
		}

		Logger.tak.info("Received fountain-coded CoT from node \(nodeNum): \(cot.type)")
		return cot
	}

	/// Send fountain ACK
	private func sendFountainAck(transferId: UInt32, hash: Data, to nodeNum: UInt32) async {
		guard let accessoryManager, let activeConnection = accessoryManager.activeConnection else {
			return
		}

		guard let deviceNum = activeConnection.device.num else {
			return
		}

		let ackPacket = FountainCodec.shared.buildAck(
			transferId: transferId,
			type: FountainConstants.ackTypeComplete,
			received: 0,
			needed: 0,
			dataHash: hash
		)

		var dataMessage = DataMessage()
		dataMessage.portnum = .atakForwarder
		dataMessage.payload = ackPacket

		var meshPacket = MeshPacket()
		meshPacket.to = nodeNum
		meshPacket.from = UInt32(deviceNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.decoded = dataMessage

		var toRadio = ToRadio()
		toRadio.packet = meshPacket

		do {
			try await accessoryManager.send(toRadio, debugDescription: "Fountain ACK")
			Logger.tak.debug("Sent fountain ACK for transfer \(transferId)")
		} catch {
			Logger.tak.warning("Failed to send fountain ACK: \(error.localizedDescription)")
		}
	}

	/// Handle incoming fountain ACK
	func handleIncomingAck(_ payload: Data, from nodeNum: UInt32) {
		guard let ack = FountainCodec.shared.parseAck(payload) else {
			Logger.tak.debug("Failed to parse fountain ACK from node \(nodeNum)")
			return
		}

		Logger.tak.debug("Received fountain ACK: xferId=\(ack.transferId), type=\(ack.type), from node \(nodeNum)")

		if let pending = pendingTransfers[ack.transferId] {
			if ack.type == FountainConstants.ackTypeComplete {
				// Verify hash matches
				if ack.dataHash == pending.dataHash {
					Logger.tak.info("Fountain transfer \(ack.transferId) acknowledged by node \(nodeNum)")
				} else {
					Logger.tak.warning("Fountain ACK hash mismatch for transfer \(ack.transferId)")
				}
				pendingTransfers.removeValue(forKey: ack.transferId)
			} else if ack.type == FountainConstants.ackTypeNeedMore {
				Logger.tak.debug("Node \(nodeNum) needs \(ack.needed) more blocks for transfer \(ack.transferId)")
				// TODO: Send additional blocks
			}
		} else {
			// No pending transfer - might be echo of our own ACK or already completed
			Logger.tak.debug("Received ACK for unknown/completed transfer \(ack.transferId)")
		}
	}
}

// MARK: - Supporting Types

/// Tracks a pending outgoing fountain transfer
private struct PendingTransfer {
	let transferId: UInt32
	let totalBlocks: Int
	let dataHash: Data
	let startTime: Date = Date()
}

/// Errors for generic CoT handling
enum GenericCoTError: LocalizedError {
	case notConnected
	case noDeviceNumber
	case compressionFailed
	case encodingFailed

	var errorDescription: String? {
		switch self {
		case .notConnected:
			return "Not connected to Meshtastic device"
		case .noDeviceNumber:
			return "No device number available"
		case .compressionFailed:
			return "Failed to compress CoT to EXI"
		case .encodingFailed:
			return "Failed to encode CoT for transmission"
		}
	}
}
