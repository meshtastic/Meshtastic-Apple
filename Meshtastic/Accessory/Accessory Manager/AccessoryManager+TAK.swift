//
//  AccessoryManager+TAK.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import MeshtasticProtobufs
import OSLog

extension AccessoryManager {

	// MARK: - TAK Server Initialization

	/// Initialize the TAK bridge when connected to a Meshtastic device
	func initializeTAKBridge() {
		let takServer = TAKServerManager.shared

		// Create the bridge
		let bridge = TAKMeshtasticBridge(
			accessoryManager: self,
			takServerManager: takServer
		)
		bridge.context = self.context

		// Assign bridge to server
		takServer.bridge = bridge

		Logger.tak.info("TAK bridge initialized")

		// Start server if enabled
		if takServer.enabled && !takServer.isRunning {
			Task {
				do {
					try await takServer.start()
					Logger.tak.info("TAK Server auto-started on connection")
				} catch {
					Logger.tak.error("Failed to auto-start TAK Server: \(error.localizedDescription)")
				}
			}
		}
	}

	/// Clean up TAK bridge when disconnecting
	func cleanupTAKBridge() {
		// Note: We don't stop the server here - it can continue running
		// even without a Meshtastic connection (for TAK connectivity)
		Logger.tak.info("TAK bridge cleanup")
	}

	// MARK: - Send TAK Packet to Mesh

	/// Send a TAK packet to the Meshtastic mesh network
	/// - Parameters:
	///   - takPacket: The TAKPacket protobuf to send
	///   - channel: Channel to send on (0 = default/primary)
	func sendTAKPacket(_ takPacket: TAKPacket, channel: UInt32 = 0) async throws {
		Logger.tak.debug("=== Sending TAKPacket to Mesh ===")

		guard let activeConnection else {
			Logger.tak.error("Not connected to Meshtastic device")
			throw AccessoryError.connectionFailed("Not connected to Meshtastic device")
		}

		guard let deviceNum = activeConnection.device.num else {
			Logger.tak.error("No device number available")
			throw AccessoryError.connectionFailed("No device number available")
		}

		Logger.tak.debug("Device num: \(deviceNum)")

		// Log TAKPacket details before serialization
		Logger.tak.debug("TAKPacket to send:")
		Logger.tak.debug("  hasContact: \(takPacket.hasContact)")
		if takPacket.hasContact {
			Logger.tak.debug("    callsign: \(takPacket.contact.callsign)")
			Logger.tak.debug("    deviceCallsign: \(takPacket.contact.deviceCallsign)")
		}
		Logger.tak.debug("  hasGroup: \(takPacket.hasGroup)")
		if takPacket.hasGroup {
			Logger.tak.debug("    team: \(takPacket.group.team.rawValue)")
			Logger.tak.debug("    role: \(takPacket.group.role.rawValue)")
		}
		Logger.tak.debug("  hasStatus: \(takPacket.hasStatus)")
		if takPacket.hasStatus {
			Logger.tak.debug("    battery: \(takPacket.status.battery)")
		}
		Logger.tak.debug("  payloadVariant: \(String(describing: takPacket.payloadVariant))")

		// Serialize the TAK packet
		let serialized: Data
		do {
			serialized = try takPacket.serializedData()
			Logger.tak.debug("Serialized TAKPacket: \(serialized.count) bytes")
			Logger.tak.debug("Serialized hex: \(serialized.map { String(format: "%02x", $0) }.joined(separator: " "))")
		} catch {
			Logger.tak.error("Failed to serialize TAKPacket: \(error.localizedDescription)")
			throw AccessoryError.ioFailed("Failed to serialize TAKPacket")
		}

		// Build the mesh packet
		var dataMessage = DataMessage()
		dataMessage.portnum = .atakPlugin  // Port 72
		dataMessage.payload = serialized

		var meshPacket = MeshPacket()
		meshPacket.to = 0xFFFFFFFF  // Broadcast
		meshPacket.from = UInt32(deviceNum)
		meshPacket.channel = channel
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.decoded = dataMessage

		Logger.tak.debug("MeshPacket:")
		Logger.tak.debug("  to: \(String(format: "0x%08X", meshPacket.to))")
		Logger.tak.debug("  from: \(String(format: "0x%08X", meshPacket.from))")
		Logger.tak.debug("  channel: \(meshPacket.channel)")
		Logger.tak.debug("  id: \(meshPacket.id)")
		Logger.tak.debug("  portnum: \(dataMessage.portnum.rawValue)")
		Logger.tak.debug("  payload size: \(serialized.count)")

		var toRadio = ToRadio()
		toRadio.packet = meshPacket

		try await send(toRadio, debugDescription: "Sending TAKPacket to mesh")

		Logger.tak.info("Sent TAKPacket to mesh (portnum=\(PortNum.atakPlugin.rawValue), channel=\(channel), size=\(serialized.count) bytes)")
		Logger.tak.debug("=== End Sending TAKPacket ===")
	}

	/// Send a CoT message to the mesh by converting it to TAKPacket first
	func sendCoTToMesh(_ cotMessage: CoTMessage, channel: UInt32 = 0) async throws {
		let bridge = TAKServerManager.shared.bridge

		guard let takPacket = bridge?.convertToTAKPacket(cot: cotMessage) else {
			throw AccessoryError.ioFailed("Failed to convert CoT to TAKPacket")
		}

		try await sendTAKPacket(takPacket, channel: channel)
	}

	// MARK: - Receive TAK Packet from Mesh

	/// Handle incoming ATAK Plugin packet from the mesh network
	/// Forwards to connected TAK clients via the bridge
	func handleATAKPluginPacket(_ packet: MeshPacket) {
		guard case let .decoded(data) = packet.payloadVariant else {
			Logger.tak.warning("Received ATAK packet without decoded payload")
			return
		}

		Logger.tak.debug("Received ATAK packet: \(data.payload.count) bytes from node \(packet.from)")

		// Check if packet is compressed (first bytes 08 01 indicate is_compressed = true)
		// Compressed packets are sent as duplicates of uncompressed ones, so we ignore them
		let payload = data.payload
		if payload.count >= 2 && payload[0] == 0x08 && payload[1] == 0x01 {
			Logger.tak.debug("Ignoring compressed TAKPacket (duplicate of uncompressed)")
			return
		}

		// Parse uncompressed TAKPacket protobuf
		let takPacket: TAKPacket
		do {
			takPacket = try TAKPacket(serializedBytes: payload)
		} catch {
			Logger.tak.warning("Failed to parse TAKPacket from mesh packet: \(error.localizedDescription)")
			Logger.tak.debug("Parse error details: \(error)")
			Logger.tak.debug("Raw payload hex: \(payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
			return
		}

		Logger.tak.info("Received TAKPacket from mesh node \(packet.from)")
		Logger.tak.debug("  hasContact: \(takPacket.hasContact), hasGroup: \(takPacket.hasGroup), hasStatus: \(takPacket.hasStatus)")
		Logger.tak.debug("  payloadVariant: \(String(describing: takPacket.payloadVariant))")

		// Forward to TAK clients via bridge
		Task {
			await TAKServerManager.shared.bridge?.broadcastToTAKClients(takPacket, from: packet.from)
		}
	}

	// MARK: - Handle ATAK Forwarder Packet (Port 257)

	/// Handle incoming ATAK_FORWARDER packet for generic CoT events
	/// These are EXI-compressed CoT XML, possibly fountain-coded for large messages
	func handleATAKForwarderPacket(_ packet: MeshPacket) {
		guard case let .decoded(data) = packet.payloadVariant else {
			Logger.tak.warning("Received ATAK_FORWARDER packet without decoded payload")
			return
		}

		Logger.tak.debug("Received ATAK_FORWARDER packet: \(data.payload.count) bytes from node \(packet.from)")

		// Process through GenericCoTHandler on main actor
		let packetCopy = packet
		let accessoryManagerRef = self
		Task { @MainActor in
			let handler = GenericCoTHandler.shared
			handler.accessoryManager = accessoryManagerRef

			if let cotMessage = handler.handleIncomingForwarderPacket(packetCopy) {
				// Forward to TAK clients via the server manager
				await TAKServerManager.shared.broadcast(cotMessage)
				Logger.tak.info("Forwarded generic CoT to TAK clients: \(cotMessage.type)")
			}
		}
	}
}
