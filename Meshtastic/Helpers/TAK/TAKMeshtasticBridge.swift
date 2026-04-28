//
//  TAKMeshtasticBridge.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import MeshtasticProtobufs
import OSLog
import SwiftData

/// Bridges CoT messages between TAK clients and the Meshtastic mesh network
/// Handles bidirectional conversion and message routing
@MainActor
final class TAKMeshtasticBridge {

	weak var accessoryManager: AccessoryManager?
	weak var takServerManager: TAKServerManager?

	/// SwiftData context for node lookups
	var context: ModelContext?

	/// Lookup table mapping callsigns to device UIDs
	/// Populated when receiving PLI packets from other TAK users
	/// Key: callsign (e.g., "OLD SALT"), Value: device UID (e.g., "ANDROID-abc123-def456")
	private var callsignToDeviceUID: [String: String] = [:]

	init(accessoryManager: AccessoryManager?, takServerManager: TAKServerManager?) {
		self.accessoryManager = accessoryManager
		self.takServerManager = takServerManager
	}

	// MARK: - Callsign to Device UID Mapping

	/// Register a callsign → device UID mapping (called when receiving PLI from other users)
	func registerContact(callsign: String, deviceUID: String) {
		guard !callsign.isEmpty, !deviceUID.isEmpty else { return }
		// Extract actual device UID in case it has a smuggled messageId
		let (actualDeviceUID, _) = Self.parseDeviceCallsign(deviceUID)
		guard !actualDeviceUID.isEmpty else { return }
		let previousUID = callsignToDeviceUID[callsign]
		callsignToDeviceUID[callsign] = actualDeviceUID
		if previousUID != actualDeviceUID {
			Logger.tak.debug("Registered contact: \(callsign) → \(actualDeviceUID)")
		}
	}

	// MARK: - Read Receipt Handling

	/// Receipt type for GeoChat read receipts
	enum ReceiptType {
		case delivered  // ACK:D - Message delivered to device
		case read       // ACK:R - Message read by user
	}

	/// Parsed read receipt from a GeoChat message
	struct ParsedReceipt {
		let type: ReceiptType
		let messageId: String
	}

	/// Check if a GeoChat message is a read receipt
	/// Receipt format: "ACK:D:<messageId>" or "ACK:R:<messageId>"
	/// - Parameter message: The GeoChat message content
	/// - Returns: Parsed receipt if this is a receipt, nil otherwise
	nonisolated static func parseReceipt(from message: String) -> ParsedReceipt? {
		guard message.hasPrefix("ACK:") else { return nil }

		let parts = message.split(separator: ":", maxSplits: 2)
		guard parts.count == 3 else {
			return nil
		}

		let receiptTypeString = String(parts[1])
		let messageId = String(parts[2])

		guard !messageId.isEmpty else { return nil }

		let receiptType: ReceiptType
		switch receiptTypeString {
		case "D":
			receiptType = .delivered
		case "R":
			receiptType = .read
		default:
			return nil
		}

		return ParsedReceipt(type: receiptType, messageId: messageId)
	}

	/// Check if a TAKPacket GeoChat is a read receipt
	nonisolated static func isReceipt(_ takPacket: TAKPacket) -> Bool {
		guard case .chat(let geoChat) = takPacket.payloadVariant else {
			return false
		}
		return geoChat.message.hasPrefix("ACK:")
	}

	// MARK: - MessageId Smuggling in device_callsign

	/// Parse a device_callsign that may contain a smuggled messageId
	/// Format: "<actual_device_callsign>|<messageId>" or just "<actual_device_callsign>"
	/// - Parameter combined: The device_callsign field value
	/// - Returns: Tuple of (actualDeviceCallsign, messageId) where messageId is nil if not present
	nonisolated static func parseDeviceCallsign(_ combined: String?) -> (deviceCallsign: String, messageId: String?) {
		guard let combined = combined, !combined.isEmpty else {
			return ("", nil)
		}

		if let separatorIndex = combined.firstIndex(of: "|") {
			let deviceCallsign = String(combined[..<separatorIndex])
			let messageId = String(combined[combined.index(after: separatorIndex)...])
			return (deviceCallsign, messageId.isEmpty ? nil : messageId)
		}

		return (combined, nil)
	}

	/// Create a smuggled device_callsign containing the messageId
	/// Format: "<actual_device_callsign>|<messageId>"
	/// - Parameters:
	///   - deviceCallsign: The actual device UID
	///   - messageId: The message ID to smuggle
	/// - Returns: Combined string with messageId appended
	nonisolated static func createSmuggledDeviceCallsign(deviceCallsign: String, messageId: String) -> String {
		return "\(deviceCallsign)|\(messageId)"
	}

	/// Look up a device UID from a callsign
	func lookupDeviceUID(forCallsign callsign: String) -> String? {
		return callsignToDeviceUID[callsign]
	}

	// MARK: - TAK → Meshtastic (CoT to TAKPacket)

	/// Send a CoT message received from TAK to the Meshtastic mesh
	func sendToMesh(_ cotMessage: CoTMessage) async {
		guard let takServerManager else {
			Logger.tak.warning("Cannot send to mesh: TAKServerManager not available")
			return
		}
		
		guard !takServerManager.userReadOnlyMode else {
			Logger.tak.info("TAK Server in read-only mode: Ignoring message from TAK client")
			return
		}

		guard let accessoryManager else {
			Logger.tak.warning("Cannot send to mesh: AccessoryManager not available")
			return
		}

		guard accessoryManager.isConnected else {
			Logger.tak.warning("Cannot send to mesh: Not connected to Meshtastic device")
			return
		}

		let channel = UInt32(TAKServerManager.shared.channel)

		// Determine send method based on CoT type
		let sendMethod = GenericCoTHandler.shared.classifySendMethod(for: cotMessage)

		switch sendMethod {
		case .takPacketPLI, .takPacketChat:
			// Use TAKPacket protobuf on ATAK_PLUGIN port (72)
			guard let takPacket = convertToTAKPacket(cot: cotMessage) else {
				Logger.tak.warning("Failed to convert CoT to TAKPacket: \(cotMessage.type)")
				return
			}

			do {
				try await accessoryManager.sendTAKPacket(takPacket, channel: channel)
				Logger.tak.info("Sent TAKPacket to mesh: \(cotMessage.type)")
			} catch {
				Logger.tak.error("Failed to send TAKPacket to mesh: \(error.localizedDescription)")
			}

		case .exiDirect, .exiFountain:
			// Use EXI compression on ATAK_FORWARDER port (257)
			GenericCoTHandler.shared.accessoryManager = accessoryManager
			do {
				try await GenericCoTHandler.shared.sendGenericCoT(cotMessage, channel: channel)
				Logger.tak.info("Sent generic CoT to mesh via ATAK_FORWARDER: \(cotMessage.type)")
			} catch {
				Logger.tak.error("Failed to send generic CoT to mesh: \(error.localizedDescription)")
			}
		}
	}

	/// Convert CoT message to Meshtastic TAKPacket protobuf
	func convertToTAKPacket(cot: CoTMessage) -> TAKPacket? {
		Logger.tak.debug("=== CoT → TAKPacket Conversion ===")
		Logger.tak.debug("CoT Input:")
		Logger.tak.debug("  uid: \(cot.uid)")
		Logger.tak.debug("  type: \(cot.type)")
		Logger.tak.debug("  lat: \(cot.latitude), lon: \(cot.longitude), hae: \(cot.hae)")
		Logger.tak.debug("  contact: \(cot.contact?.callsign ?? "nil")")
		Logger.tak.debug("  group: \(cot.group?.name ?? "nil") / \(cot.group?.role ?? "nil")")
		Logger.tak.debug("  status.battery: \(cot.status?.battery ?? -1)")
		Logger.tak.debug("  track: speed=\(cot.track?.speed ?? -1), course=\(cot.track?.course ?? -1)")
		Logger.tak.debug("  chat: \(cot.chat?.message ?? "nil")")
		Logger.tak.debug("  remarks: \(cot.remarks ?? "nil")")

		var takPacket = TAKPacket()

		// Contact information
		if let contact = cot.contact {
			var cotContact = Contact()
			cotContact.callsign = contact.callsign
			cotContact.deviceCallsign = cot.uid
			takPacket.contact = cotContact
			Logger.tak.debug("TAKPacket.contact: callsign=\(cotContact.callsign), deviceCallsign=\(cotContact.deviceCallsign)")
		}

		// Group/Team information
		if let group = cot.group {
			var cotGroup = Group()
			cotGroup.team = Team.fromColorName(group.name)
			cotGroup.role = MemberRole.fromRoleName(group.role)
			takPacket.group = cotGroup
			Logger.tak.debug("TAKPacket.group: team=\(cotGroup.team.rawValue), role=\(cotGroup.role.rawValue)")
		}

		// Status (battery)
		if let status = cot.status {
			var cotStatus = Status()
			cotStatus.battery = UInt32(max(0, status.battery))
			takPacket.status = cotStatus
			Logger.tak.debug("TAKPacket.status: battery=\(cotStatus.battery)")
		}

		// Determine payload type based on CoT type
		// Accept any friendly ground unit type (a-f-G...) for PLI
		if cot.type.hasPrefix("a-f-G") || cot.type.hasPrefix("a-f-g") {
			// Register this TAK client's contact info for future DM lookups
			if let contact = cot.contact, !contact.callsign.isEmpty, !cot.uid.isEmpty {
				registerContact(callsign: contact.callsign, deviceUID: cot.uid)
			}

			// Atom type (position) - create PLI
			var pli = PLI()

			// Convert lat/lon to integer format (degrees * 1e7)
			let latI = Int32(cot.latitude * 1e7)
			let lonI = Int32(cot.longitude * 1e7)

			// Handle altitude - clamp to valid Int32 range, use 0 for unknown (9999999)
			let altitudeValue: Int32
			if cot.hae >= 9999999.0 || cot.hae.isNaN || cot.hae.isInfinite {
				altitudeValue = 0  // Unknown altitude
			} else {
				altitudeValue = Int32(clamping: Int(cot.hae))
			}

			pli.latitudeI = latI
			pli.longitudeI = lonI
			pli.altitude = altitudeValue

			if let track = cot.track {
				pli.speed = UInt32(max(0, track.speed))
				pli.course = UInt32(max(0, track.course))
			}

			takPacket.pli = pli

			Logger.tak.debug("TAKPacket.pli created:")
			Logger.tak.debug("  latitudeI: \(pli.latitudeI) (from \(cot.latitude))")
			Logger.tak.debug("  longitudeI: \(pli.longitudeI) (from \(cot.longitude))")
			Logger.tak.debug("  altitude: \(pli.altitude) (from \(cot.hae))")
			Logger.tak.debug("  speed: \(pli.speed), course: \(pli.course)")

		} else if cot.type == "b-t-f" {
			// Chat message - MUST include contact field for sender identification
			var geoChat = GeoChat()

			// Extract messageId from CoT uid if present
			// CoT uid format: "GeoChat.{senderUid}.{chatroom}.{messageId}"
			var messageId: String?
			var actualDeviceUid = cot.uid
			let uidComponents = cot.uid.components(separatedBy: ".")
			if uidComponents.count >= 4 && uidComponents[0] == "GeoChat" {
				// Extract the actual device UID (second component)
				actualDeviceUid = uidComponents[1]
				// Extract messageId (last component)
				messageId = uidComponents.last
				Logger.tak.debug("GeoChat: Extracted messageId=\(messageId ?? "nil") from uid")
			}

			// If no messageId found, generate one
			if messageId == nil || messageId?.isEmpty == true {
				messageId = UUID().uuidString
				Logger.tak.debug("GeoChat: Generated new messageId=\(messageId!)")
			}

			// Ensure contact (sender info) is always set for chat messages
			// This is REQUIRED for Android ATAK to process the message correctly
			if !takPacket.hasContact {
				var senderContact = Contact()
				// Get sender callsign from chat.senderCallsign or cot.contact
				if let senderCallsign = cot.chat?.senderCallsign, !senderCallsign.isEmpty {
					senderContact.callsign = senderCallsign
				} else if let contactCallsign = cot.contact?.callsign, !contactCallsign.isEmpty {
					senderContact.callsign = contactCallsign
				} else {
					senderContact.callsign = "Unknown"
				}
				// Smuggle messageId into device_callsign for proper threading on Android
				// Format: "<deviceUid>|<messageId>"
				senderContact.deviceCallsign = Self.createSmuggledDeviceCallsign(
					deviceCallsign: actualDeviceUid,
					messageId: messageId!
				)
				takPacket.contact = senderContact
				Logger.tak.debug("GeoChat: Added sender contact - callsign=\(senderContact.callsign), smuggled deviceCallsign=\(senderContact.deviceCallsign)")
			} else {
				// Contact already set, but we still need to smuggle the messageId
				var updatedContact = takPacket.contact
				let existingDeviceCallsign = updatedContact.deviceCallsign.isEmpty ? actualDeviceUid : updatedContact.deviceCallsign
				updatedContact.deviceCallsign = Self.createSmuggledDeviceCallsign(
					deviceCallsign: existingDeviceCallsign,
					messageId: messageId!
				)
				takPacket.contact = updatedContact
				Logger.tak.debug("GeoChat: Updated contact with smuggled messageId - deviceCallsign=\(updatedContact.deviceCallsign)")
			}

			if let chat = cot.chat {
				geoChat.message = chat.message

				// Handle recipient addressing
				// chat.chatroom contains either "All Chat Rooms" or the recipient's callsign
				if chat.chatroom == "All Chat Rooms" {
					// Broadcast message - set to literal "All Chat Rooms"
					geoChat.to = "All Chat Rooms"
					Logger.tak.debug("GeoChat: Broadcast to All Chat Rooms")
				} else {
					// Direct message - need to look up recipient's device UID from their callsign
					let recipientCallsign = chat.chatroom
					if let recipientDeviceUID = lookupDeviceUID(forCallsign: recipientCallsign) {
						// Found the recipient's device UID
						geoChat.to = recipientDeviceUID
						geoChat.toCallsign = recipientCallsign
						Logger.tak.debug("GeoChat DM: to=\(recipientDeviceUID), toCallsign=\(recipientCallsign)")
					} else {
						// Recipient device UID not found - use callsign as fallback
						// This may not work on Android but is better than nothing
						geoChat.to = recipientCallsign
						geoChat.toCallsign = recipientCallsign
						Logger.tak.warning("GeoChat DM: Unknown device UID for '\(recipientCallsign)', using callsign as fallback")
					}
				}
			} else if let remarks = cot.remarks {
				geoChat.message = remarks
				geoChat.to = "All Chat Rooms"
			}

			takPacket.chat = geoChat

			Logger.tak.debug("TAKPacket.chat created:")
			Logger.tak.debug("  message: \(geoChat.message)")
			Logger.tak.debug("  to: \(geoChat.to)")
			Logger.tak.debug("  toCallsign: \(geoChat.toCallsign)")
			Logger.tak.debug("  sender.callsign: \(takPacket.contact.callsign)")
			Logger.tak.debug("  sender.deviceCallsign: \(takPacket.contact.deviceCallsign)")

		} else {
			// Unknown type, skip
			Logger.tak.debug("Skipping CoT type not mapped to TAKPacket: \(cot.type)")
			return nil
		}

		// Log the final TAKPacket structure
		Logger.tak.debug("TAKPacket output:")
		Logger.tak.debug("  hasContact: \(takPacket.hasContact)")
		Logger.tak.debug("  hasGroup: \(takPacket.hasGroup)")
		Logger.tak.debug("  hasStatus: \(takPacket.hasStatus)")
		Logger.tak.debug("  payloadVariant: \(String(describing: takPacket.payloadVariant))")

		// Log serialized size for debugging
		do {
			let serialized = try takPacket.serializedData()
			Logger.tak.debug("  serializedSize: \(serialized.count) bytes")
			Logger.tak.debug("  serializedHex: \(serialized.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " "))\(serialized.count > 64 ? "..." : "")")
		} catch {
			Logger.tak.error("  Failed to serialize TAKPacket: \(error.localizedDescription)")
		}

		Logger.tak.debug("=== End Conversion ===")
		return takPacket
	}

	// MARK: - Meshtastic → TAK (TAKPacket to CoT)

	/// Broadcast a Meshtastic TAKPacket to all connected TAK clients
	func broadcastToTAKClients(_ takPacket: TAKPacket, from nodeNum: UInt32) async {
		// Register contact info from incoming TAKPackets (for callsign → deviceUID lookup)
		if takPacket.hasContact {
			let callsign = takPacket.contact.callsign
			let deviceUID = takPacket.contact.deviceCallsign
			if !callsign.isEmpty && !deviceUID.isEmpty {
				registerContact(callsign: callsign, deviceUID: deviceUID)
			}
		}

		// Check if this is a read receipt - don't forward to TAK clients as chat message
		if case .chat(let geoChat) = takPacket.payloadVariant {
			if let receipt = Self.parseReceipt(from: geoChat.message) {
				// This is a read receipt, handle it internally
				let typeString = receipt.type == .delivered ? "Delivered" : "Read"
				Logger.tak.info("Received \(typeString) receipt for messageId: \(receipt.messageId) from node \(nodeNum)")
				// TODO: Update message status in Core Data if we track sent messages
				// For now, just log and don't forward to TAK clients
				return
			}
		}

		guard let takServerManager else {
			Logger.tak.debug("Cannot broadcast to TAK: TAKServerManager not available")
			return
		}

		guard takServerManager.isRunning else {
			Logger.tak.debug("Cannot broadcast to TAK: Server not running")
			return
		}

		guard !takServerManager.connectedClients.isEmpty else {
			Logger.tak.debug("No TAK clients connected, skipping broadcast")
			return
		}

		// Look up node info for additional context
		let nodeInfo = lookupNodeInfo(nodeNum: nodeNum)

		// Convert to CoT
		guard let cotMessage = convertToCoT(from: takPacket, nodeNum: nodeNum, nodeInfo: nodeInfo) else {
			Logger.tak.warning("Failed to convert TAKPacket to CoT from node \(nodeNum)")
			return
		}

		// Broadcast to all TAK clients
		await takServerManager.broadcast(cotMessage)
		Logger.tak.info("Broadcast CoT to TAK clients: \(cotMessage.type) from node \(nodeNum)")
	}

	/// Convert Meshtastic TAKPacket to CoT message
	func convertToCoT(from takPacket: TAKPacket, nodeNum: UInt32, nodeInfo: NodeInfoEntity?) -> CoTMessage? {
		// Use the factory method from CoTMessage which handles the conversion
		let deviceUid = "MESHTASTIC-\(String(format: "%08X", nodeNum))"
		return CoTMessage.fromTAKPacket(takPacket, deviceUid: deviceUid)
	}

	/// Create a CoT PLI message from a Meshtastic node's position
	func createCoTFromNode(_ node: NodeInfoEntity) -> CoTMessage? {
		guard let position = node.latestPosition,
			  let latitude = position.latitude,
			  let longitude = position.longitude,
			  latitude != 0 || longitude != 0 else {
			return nil
		}

		let uid = "MESHTASTIC-\(String(format: "%08X", node.num))"
		// Format: "SHORT - Long Name" or just "ShortName" if no long name
		let callsign: String
		if let shortName = node.user?.shortName, let longName = node.user?.longName, !longName.isEmpty {
			callsign = "\(shortName) - \(longName)"
		} else {
			callsign = node.user?.shortName ?? node.user?.longName ?? "MESH-\(node.num)"
		}

		// Get telemetry from device metrics
		let deviceMetrics = node.latestDeviceMetrics
		let battery = Int(deviceMetrics?.batteryLevel ?? 100)
		let voltage = deviceMetrics?.voltage ?? 0
		let channelUtil = deviceMetrics?.channelUtilization ?? 0
		let rssi = deviceMetrics?.rssi ?? 0
		let snr = deviceMetrics?.snr ?? 0
		
		// Build remarks with telemetry info
		var remarks = "Battery: \(battery)%"
		if voltage > 0 {
			remarks += " | Voltage: \(String(format: "%.2f", voltage))V"
		}
		if channelUtil > 0 {
			remarks += " | Chan Util: \(String(format: "%.1f", channelUtil))%"
		}
		if rssi != 0 {
			remarks += " | RSSI: \(rssi) dBm"
		}
		if snr != 0 {
			remarks += " | SNR: \(String(format: "%.1f", snr)) dB"
		}
		
		return CoTMessage.pli(
			uid: uid,
			callsign: callsign,
			latitude: latitude,
			longitude: longitude,
			altitude: Double(position.altitude),
			speed: Double(position.speed),
			course: Double(position.heading),
			team: "Green",  // Meshtastic nodes shown as green by default
			role: "Team Member",
			battery: battery,
			staleMinutes: 15,  // Meshtastic positions can be older
			remarks: remarks
		)
	}

	// MARK: - Broadcast All Mesh Nodes to TAK

	/// Send all known mesh node positions to TAK clients
	/// Useful when a new TAK client connects
	/// Only sends nodes with positions updated within the last 2 hours
	/// Excludes the node we're currently connected to
	func broadcastAllNodesToTAK() async {
		guard let takServerManager, takServerManager.isRunning else { return }
		
		// Get context - try the bridge's context first, then fall back to PersistenceController
		let context = self.context ?? PersistenceController.shared.context
		
		let twoHoursAgo = Date().addingTimeInterval(-7200)
		
		// Get the connected node number to exclude it
		let connectedNodeNum = AccessoryManager.shared.activeDeviceNum ?? 0
		
		Logger.tak.info("Starting broadcast of all mesh nodes to TAK (excluding node \(connectedNodeNum))")
		
		// Fetch all nodes - be more lenient, include any node that's been heard from
		// We'll check positions when creating CoT messages
		let descriptor = FetchDescriptor<NodeInfoEntity>()
		
		do {
			let nodes = try context.fetch(descriptor)
				.filter { $0.user != nil }
				.sorted { ($0.lastHeard ?? .distantPast) > ($1.lastHeard ?? .distantPast) }
			Logger.tak.info("Found \(nodes.count) total nodes with user info, connected node: \(connectedNodeNum)")
			
			var broadcastCount = 0
			var skippedNoPosition = 0
			var skippedConnected = 0
			var skippedInvalidPosition = 0
			var skippedTooOld = 0
			
			for node in nodes {
				// Skip the connected node - it's our own device
				// Use the same pattern as other parts of the codebase: node.num == accessoryManager.activeDeviceNum
				if node.num == connectedNodeNum {
					Logger.tak.info("Skipping connected node \(node.num)")
					skippedConnected += 1
					continue
				}
				
				// Get position - use the extension's latestPosition computed property
				guard let position = node.latestPosition,
					  let latitude = position.latitude,
					  let longitude = position.longitude else {
					skippedNoPosition += 1
					continue
				}
				
				// Skip nodes with invalid positions (0,0)
				guard latitude != 0 || longitude != 0 else {
					skippedInvalidPosition += 1
					continue
				}
				
				// Check if node has been heard from recently (within last 2 hours)
				if let lastHeard = node.lastHeard, lastHeard < twoHoursAgo {
					skippedTooOld += 1
					continue
				}
				
				if let cotMessage = createCoTFromNode(node) {
					await takServerManager.broadcast(cotMessage)
					broadcastCount += 1
					
					// Small delay to avoid flooding the client
					try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
				}
			}

			Logger.tak.info("Broadcast complete: \(broadcastCount) nodes sent, \(skippedConnected) skipped (connected), \(skippedNoPosition) skipped (no position), \(skippedInvalidPosition) skipped (invalid position), \(skippedTooOld) skipped (too old)")
		} catch {
			Logger.tak.error("Failed to fetch nodes for TAK broadcast: \(error.localizedDescription)")
		}
	}

	// MARK: - Helper Methods

	private func lookupNodeInfo(nodeNum: UInt32) -> NodeInfoEntity? {
		// Use PersistenceController's viewContext directly to ensure we can find nodes
		let context = PersistenceController.shared.context

		let descriptor = FetchDescriptor<NodeInfoEntity>()

		do {
			let nodeNumInt64 = Int64(nodeNum)
			return try context.fetch(descriptor).first { $0.num == nodeNumInt64 }
		} catch {
			Logger.tak.warning("Failed to lookup node info for \(nodeNum): \(error.localizedDescription)")
			return nil
		}
	}
	
	// MARK: - Mesh to CoT Broadcasting
	
	/// Broadcast a Meshtastic position packet to connected TAK clients
	/// Called when a new position is received from the mesh
	func broadcastMeshPositionToTAK(position: Position, from nodeNum: UInt32) async {
		// Lazy initialization of bridge if needed
		if TAKServerManager.shared.bridge == nil {
			Logger.tak.info("Initializing bridge lazily for position broadcast")
			let bridge = TAKMeshtasticBridge(
				accessoryManager: AccessoryManager.shared,
				takServerManager: TAKServerManager.shared
			)
			bridge.context = AccessoryManager.shared.context
			TAKServerManager.shared.bridge = bridge
		}
		
		let server = TAKServerManager.shared
		guard server.meshToCotEnabled, server.isRunning else { return }
		guard server.connectedClients.isEmpty == false else { return }
		
		guard let node = lookupNodeInfo(nodeNum: nodeNum) else { return }
		
		if let cotMessage = createCoTFromNode(node) {
			await server.broadcast(cotMessage)
			Logger.tak.info("Broadcast mesh position to TAK: \(node.user?.longName ?? "Unknown")")
		}
	}
	
	/// Broadcast a Meshtastic text message to connected TAK clients
	/// Called when a text message is received from the mesh
	/// - Parameters:
	///   - text: The message text
	///   - from: The sender node number
	///   - channel: The channel index
	///   - to: The destination node number (UInt32.max for broadcast)
	func broadcastMeshTextMessageToTAK(text: String, from nodeNum: UInt32, channel: UInt32, to destination: UInt32) async {
		// Lazy initialization of bridge if needed
		if TAKServerManager.shared.bridge == nil {
			Logger.tak.info("Initializing bridge lazily for text message broadcast")
			let bridge = TAKMeshtasticBridge(
				accessoryManager: AccessoryManager.shared,
				takServerManager: TAKServerManager.shared
			)
			bridge.context = AccessoryManager.shared.context
			TAKServerManager.shared.bridge = bridge
		}
		
		let server = TAKServerManager.shared
		guard server.meshToCotEnabled, server.isRunning else { return }
		guard server.connectedClients.isEmpty == false else { return }
		
		guard let node = lookupNodeInfo(nodeNum: nodeNum),
			  let user = node.user else { return }
		
		let senderName = user.longName ?? user.shortName ?? "Unknown"
		let uid = "MSG-\(nodeNum)-\(Int(Date().timeIntervalSince1970))"
		
		// Determine if this is a DM or broadcast
		let isDirectMessage = destination != UInt32.max
		
		// For now, send all messages to general chat but mark DMs in the message
		let chatroom = "All Chat Rooms"
		
		Logger.tak.info("Text message: isDM=\(isDirectMessage), chatroom=\(chatroom), from=\(senderName)")
		
		let senderUid = "MESHTASTIC-\(String(format: "%08X", nodeNum))"
		
		// Prefix DM messages with "DM:" so users know it's a direct message
		let messageText = isDirectMessage ? "DM: \(text)" : text
		
		let cotMessage = CoTMessage(
			uid: "GeoChat.\(senderUid).\(chatroom.replacingOccurrences(of: " ", with: "_")).\(uid)",
			type: "b-t-f",
			time: Date(),
			start: Date(),
			stale: Date().addingTimeInterval(86400),
			how: "h-g-i-g-o",
			latitude: 0,
			longitude: 0,
			hae: 9999999.0,
			ce: 9999999.0,
			le: 9999999.0,
			contact: CoTContact(callsign: senderName, endpoint: "0.0.0.0:4242:tcp"),
			chat: CoTChat(
				message: messageText,
				senderCallsign: senderName,
				chatroom: chatroom
			),
			remarks: messageText
		)
		
		await server.broadcast(cotMessage)
		Logger.tak.info("Broadcast mesh text message to TAK: \(senderName) to \(chatroom)")
	}
	
	/// Broadcast a Meshtastic waypoint to connected TAK clients
	/// Called when a waypoints is received from the mesh
	func broadcastMeshWaypointToTAK(waypoint: Waypoint, from nodeNum: UInt32) async {
		// Lazy initialization of bridge if needed - set on singleton
		if TAKServerManager.shared.bridge == nil {
			Logger.tak.info("Initializing bridge lazily on singleton")
			let bridge = TAKMeshtasticBridge(
				accessoryManager: AccessoryManager.shared,
				takServerManager: TAKServerManager.shared
			)
			bridge.context = AccessoryManager.shared.context
			TAKServerManager.shared.bridge = bridge
		}
		
		let server = TAKServerManager.shared
		Logger.tak.info("Waypoint broadcast check: meshToCot=\(server.meshToCotEnabled), isRunning=\(server.isRunning), clients=\(server.connectedClients.count)")
		
		guard server.meshToCotEnabled, server.isRunning else { 
			Logger.tak.warning("Waypoint broadcast skipped: server not ready")
			return 
		}
		guard let context, server.connectedClients.isEmpty == false else { 
			Logger.tak.warning("Waypoint broadcast skipped: no clients")
			return 
		}
		
		let node = lookupNodeInfo(nodeNum: nodeNum)
		Logger.tak.info("Node lookup for \(nodeNum) (0x\(String(format: "%08X", nodeNum))): \(node != nil ? "found" : "NOT FOUND")")
		if let node = node {
			Logger.tak.info("  Node user: \(node.user?.longName ?? "nil"), shortName: \(node.user?.shortName ?? "nil")")
		}
		let senderName = node?.user?.longName ?? node?.user?.shortName ?? "Unknown Node"
		
		let uid = "WAYPOINT-\(waypoint.id)"
		let latitude = Double(waypoint.latitudeI) / 1e7
		let longitude = Double(waypoint.longitudeI) / 1e7
		
		let name = waypoint.name.isEmpty ? "Dropped Pin" : waypoint.name
		let description = waypoint.description_p.isEmpty ? "Meshtastic Waypoint" : waypoint.description_p
		
		Logger.tak.info("Broadcasting waypoint: \(name) at \(latitude), \(longitude), sender: \(senderName)")
		
		// Map Meshtastic emoji icon to appropriate TAK icon
		let (cotType, iconPath, colorArgb) = getTakIconForWaypoint(waypoint: waypoint)
		let userIconXML = "<usericon iconsetpath='\(iconPath)'/>"
		Logger.tak.info("Waypoint icon: emoji=0x\(String(format: "%08X", waypoint.icon)) -> \(iconPath)")
		
		// Handle expiry - if expire is 0, never expire. Otherwise use the expire time
		let stale: Date
		if waypoint.expire == 0 {
			// Never expire - set to 1 year from now
			stale = Date().addingTimeInterval(365 * 24 * 60 * 60)
			Logger.tak.info("Waypoint set to never expire")
		} else {
			// expire is Unix timestamp when waypoint expires
			let expireDate = Date(timeIntervalSince1970: TimeInterval(waypoint.expire))
			if expireDate > Date() {
				stale = expireDate
			} else {
				// Already expired, don't broadcast
				Logger.tak.warning("Waypoint already expired, skipping broadcast")
				return
			}
		}
		
		// Include the usericon in the detail (no color to avoid background in TAKware)
		let rawDetail = "<precisionlocation geopointsrc='GPS' altsrc='GPS'></precisionlocation>\(userIconXML)"
		
		let cotMessage = CoTMessage(
			uid: uid,
			type: cotType,
			time: Date(),
			start: Date(),
			stale: stale,
			how: "m-g",
			latitude: latitude,
			longitude: longitude,
			hae: 0,
			ce: 10.0,
			le: 10.0,
			contact: CoTContact(callsign: "\(name) - \(senderName)", endpoint: "0.0.0.0:4242:tcp"),
			remarks: "\(description)\nFrom: \(senderName) [\(String(format: "%08X", nodeNum))]",
			rawDetailXML: rawDetail
		)
		
		await server.broadcast(cotMessage)
		Logger.tak.info("Broadcast mesh waypoint to TAK: \(name) from \(senderName)")
	}
	
	/// Map Meshtastic waypoint emoji to TAK icon
	/// Returns (cotType, iconPath, colorArgb)
	/// Icon paths use format: UUID/Category/icon.png
	/// Priority: Google > Generic Icons (fallback)
	private func getTakIconForWaypoint(waypoint: Waypoint) -> (String, String, String) {
		let icon = waypoint.icon
		
		// Icon set UUIDs
		let googleUUID = "f7f71666-8b28-4b57-9fbb-e38e61d33b79"
		let genericUUID = "ad78aafb-83a6-4c07-b2b9-a897a8b6a38f"
		
		switch icon {
		// 📍 📌 Pushpin - RED pushpin (default)
		case 0x1F4CD, 0x1F4CC, 1: // 📍 📌
			return ("a-u-G", "\(genericUUID)/Tacks/red-pushpin.png", "-16776961")
			
		// === EMERGENCY ===
		// 🔥 Fire - Google firedept
		case 0x1F525, 10: // 🔥
			return ("a-u-G", "\(googleUUID)/Google/firedept.png", "-16776961")
		// 🚨 Siren - Google caution
		case 0x1F6A8, 6: // 🚨
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-256")
		// 🏥 Hospital - Google hospitals
		case 0x1F3E5, 0x2695, 9: // 🏥 ➕
			return ("a-u-G", "\(googleUUID)/Google/hospitals.png", "-16776961")
		// 🚑 Ambulance - Google hospitals (no ambulance in Google)
		case 0x1F691: // 🚑
			return ("a-u-G", "\(googleUUID)/Google/hospitals.png", "-16776961")
		// ⚠️ Warning - Google caution
		case 0x26A0: // ⚠️
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-256")
		// 🚓 Police - Google police
		case 0x1F693: // 🚓
			return ("a-u-G", "\(googleUUID)/Google/police.png", "-16776961")
		// 🏃 Runner - Google man
		case 0x1F3C3: // 🏃
			return ("a-u-G", "\(googleUUID)/Google/man.png", "-16711936")
		// 💀 Skull - Google caution
		case 0x1F480: // 💀
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-1")
		// 💣 Bomb - Google caution
		case 0x1F4A3: // 💣
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-16776961")
			
		// === TRANSPORT ===
		// 🚗 Car - Google bus (closest)
		case 0x1F697, 0x1F695, 2: // 🚗 🚕
			return ("a-u-G", "\(googleUUID)/Google/bus.png", "-256")
		// 🚁 Helicopter - Google heliport
		case 0x1F681, 11: // 🚁
			return ("a-u-G", "\(googleUUID)/Google/heliport.png", "-16776961")
		// ⛵ Boat - Google marina
		case 0x26F5, 12: // ⛵
			return ("a-u-G", "\(googleUUID)/Google/marina.png", "-16776961")
		// 🚢 Ship - Google marina
		case 0x1F6A2: // 🚢
			return ("a-u-G", "\(googleUUID)/Google/marina.png", "-16776961")
		// 🚀 Rocket - Google target
		case 0x1F680: // 🚀
			return ("a-u-G", "\(googleUUID)/Google/target.png", "-16776961")
		// 🛸 UFO - Generic purple pushpin
		case 0x1F6B8, 13: // 🛸
			return ("a-u-G", "\(genericUUID)/Tacks/purple-pushpin.png", "-65281")
		// 🚲 Bicycle - Google cycling
		case 0x1F6B2: // 🚲
			return ("a-u-G", "\(googleUUID)/Google/cycling.png", "-16711936")
		// 🚆 Train - Google rail
		case 0x1F686: // 🚆
			return ("a-u-G", "\(googleUUID)/Google/rail.png", "-16711936")
		// ✈️ Plane - Google airports
		case 0x2708: // ✈️
			return ("a-u-G", "\(googleUUID)/Google/airports.png", "-16776961")
		// 🚛 Truck - Google bus
		case 0x1F69A: // 🚛
			return ("a-u-G", "\(googleUUID)/Google/bus.png", "-16711936")
		// 🚌 Bus - Google bus
		case 0x1F68C: // 🚌
			return ("a-u-G", "\(googleUUID)/Google/bus.png", "-256")
			
		// === PLACES ===
		// 🏨 Hotel - Google lodging
		case 0x1F3E8: // 🏨
			return ("a-u-G", "\(googleUUID)/Google/lodging.png", "-16776961")
		// 🏪 Store - Google convenience
		case 0x1F3EA: // 🏪
			return ("a-u-G", "\(googleUUID)/Google/convenience.png", "-16711936")
		// ⛽ Gas - Google gas_stations
		case 0x1F6FD: // ⛽
			return ("a-u-G", "\(googleUUID)/Google/gas_stations.png", "-16776961")
		// 🏰 Castle - Google info
		case 0x1F3F0: // 🏰
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🏛️ Government - Google info
		case 0x1F3DB: // 🏛️
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// ⛲ Fountain - Generic fountain (use info)
		case 0x1F6F1: // ⛲
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🏞️ Park - Google parks
		case 0x1F3DE: // 🏞️
			return ("a-u-G", "\(googleUUID)/Google/parks.png", "-16711936")
			
		// === PEOPLE ===
		// 🚶 Person - Google hiker
		case 0x1F464, 0x1F465, 3: // 👤 👥
			return ("a-u-G", "\(googleUUID)/Google/hiker.png", "-16711936")
			
		// === STRUCTURES ===
		// 🏠 House - Google homegardenbusiness
		case 0x1F3E0, 0x1F3E1, 4: // 🏠 🏡
			return ("a-u-G", "\(googleUUID)/Google/homegardenbusiness.png", "-16711936")
		// ⛺ Tent - Google campground
		case 0x26FA, 0x1F3D5, 5: // ⛺ 🏕
			return ("a-u-G", "\(googleUUID)/Google/campground.png", "-256")
		// 🏚️ Abandoned - Google info
		case 0x1F6DA: // 🏚️
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🏗️ Construction - Google caution
		case 0x1F6D7: // 🏗️
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-16776961")
		// 🏭 Factory - Google info
		case 0x1F3ED: // 🏭
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
			
		// === NATURE / TERRAIN ===
		// 🌲 Tree - Google parks
		case 0x1F332: // 🌲
			return ("a-u-G", "\(googleUUID)/Google/parks.png", "-16711936")
		// 🌳 Tree - Google parks
		case 0x1F333: // 🌳
			return ("a-u-G", "\(googleUUID)/Google/parks.png", "-16711936")
		// 🏔️ Mountain - Google cross-hairs
		case 0x1F3D4: // 🏔️
			return ("a-u-G", "\(googleUUID)/Google/cross-hairs.png", "-1")
		// ⛰️ Mountain - Google cross-hairs
		case 0x26F0: // ⛰️
			return ("a-u-G", "\(googleUUID)/Google/cross-hairs.png", "-1")
		// 💧 Water - Google water
		case 0x1F4A7: // 💧
			return ("a-u-G", "\(googleUUID)/Google/water.png", "-16776961")
		// 🌊 Wave - Google water
		case 0x1F30A: // 🌊
			return ("a-u-G", "\(googleUUID)/Google/water.png", "-16776961")
		// ☁️ Cloud - Google partly_cloudy
		case 0x2601, 0x2602: // ☁ ☂
			return ("a-u-G", "\(googleUUID)/Google/partly_cloudy.png", "-1")
		// 🌙 Moon - Google star
		case 0x1F319: // 🌙
			return ("a-u-G", "\(googleUUID)/Google/star.png", "-16776961")
		// ⚓ Anchor - Google marina
		case 0x2693: // ⚓
			return ("a-u-G", "\(googleUUID)/Google/marina.png", "-16776961")
		// ⭐ Star - Google star
		case 0x2B50, 0x1F31F: // ⭐ 🌟
			return ("a-u-G", "\(googleUUID)/Google/star.png", "-256")
		// 🌞 Sun - Google sunny
		case 0x1F31E: // 🌞
			return ("a-u-G", "\(googleUUID)/Google/sunny.png", "-256")
			
		// === FLAGS/MARKERS ===
		// 🚩 Flag - Google flag
		case 0x1F6A9: // 🚩
			return ("a-u-G", "\(googleUUID)/Google/flag.png", "-16776961")
		// 🏁 Checkered flag - Google flag
		case 0x1F3C1, 7: // 🏁
			return ("a-u-G", "\(googleUUID)/Google/flag.png", "-1")
		// 🎌 Flags - Google flag
		case 0x1F38C: // 🎌
			return ("a-u-G", "\(googleUUID)/Google/flag.png", "-16776961")
			
		// === OBJECTS ===
		// 📷 Camera - Google camera
		case 0x1F4F7: // 📷
			return ("a-u-G", "\(googleUUID)/Google/camera.png", "-16711936")
		// 🔒 Lock - Google info
		case 0x1F512: // 🔒
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
		// 🔑 Key - Google info
		case 0x1F511: // 🔑
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
		// 📦 Package - Google shopping
		case 0x1F4E6: // 📦
			return ("a-u-G", "\(googleUUID)/Google/shopping.png", "-16711936")
		// 🚧 Construction - Google caution
		case 0x1F6A7: // 🚧
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-256")
		// 🎯 Target - Google target
		case 0x1F3AF: // 🎯
			return ("a-u-G", "\(googleUUID)/Google/target.png", "-16776961")
		// 🏹 Sports bow - Google target
		case 0x1F3F9: // 🏹
			return ("a-u-G", "\(googleUUID)/Google/target.png", "-16776961")
		// 🔧 Wrench - Google mechanic
		case 0x1F527: // 🔧
			return ("a-u-G", "\(googleUUID)/Google/mechanic.png", "-16711936")
		// 🛠️ Tools - Google mechanic
		case 0x1F6E0: // 🛠️
			return ("a-u-G", "\(googleUUID)/Google/mechanic.png", "-16711936")
		// 📮 Post box - Google post_office
		case 0x1F4EE: // 📮
			return ("a-u-G", "\(googleUUID)/Google/post_office.png", "-16776961")
		// 💎 Gem - Google star
		case 0x1F48E: // 💎
			return ("a-u-G", "\(googleUUID)/Google/star.png", "-16776961")
		// 🔔 Bell - Google info
		case 0x1F514: // 🔔
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-256")
		// 🎁 Gift - Google shopping
		case 0x1F381: // 🎁
			return ("a-u-G", "\(googleUUID)/Google/shopping.png", "-16776961")
		// ❄️ Snowflake - Google snowflake_simple
		case 0x2744: // ❄
			return ("a-u-G", "\(googleUUID)/Google/snowflake_simple.png", "-1")
		// ☂️ Umbrella - Google sunny
		case 0x26F1: // ⛱
			return ("a-u-G", "\(googleUUID)/Google/sunny.png", "-16776961")
		// 💡 Light - Google info-i
		case 0x1F4A1: // 💡
			return ("a-u-G", "\(googleUUID)/Google/info-i.png", "-256")
		// 🔋 Battery - Google bars
		case 0x1F50B: // 🔋
			return ("a-u-G", "\(googleUUID)/Google/bars.png", "-16711936")
		// 📻 Radio - Google radio
		case 0x1F4FB: // 📻
			return ("a-u-G", "\(googleUUID)/Google/radio.png", "-16711936")
		// 📞 Phone - Google phone
		case 0x1F4DE, 0x1F4F1: // 📞 📱
			return ("a-u-G", "\(googleUUID)/Google/phone.png", "-16711936")
		// 💥 Collision - Google caution
		case 0x1F4A5: // 💥
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-16776961")
		// 🔦 Flashlight - Google sunny
		case 0x1F526: // 🔦
			return ("a-u-G", "\(googleUUID)/Google/sunny.png", "-16711936")
		// 🕯️ Candle - Google sunny
		case 0x1F56F: // 🕯️
			return ("a-u-G", "\(googleUUID)/Google/sunny.png", "-16776961")
		// 📺 TV - Google camera
		case 0x1F4FA: // 📺
			return ("a-u-G", "\(googleUUID)/Google/camera.png", "-16711936")
		// 💾 Disk - Google info
		case 0x1F4BE: // 💾
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
		// 📀 DVD - Google info
		case 0x1F4C0: // 📀
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🖥️ Computer - Google info
		case 0x1F5A5: // 🖥️
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
		// ⌨️ Keyboard - Google info
		case 0x1F5A8: // ⌨️
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
		// 🖱️ Mouse - Google info
		case 0x1F5B1: // 🖱️
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
			
		// === SYMBOLS ===
		// ❤️ Heart - Google flag
		case 0x2764, 0x1F493, 0x1F49A, 0x1F499: // ❤️ 💓 💚 💙
			return ("a-u-G", "\(googleUUID)/Google/flag.png", "-16776961")
		// ✅ Check - Google star
		case 0x2705, 0x1F7E2: // ✅ 🟢
			return ("a-u-G", "\(googleUUID)/Google/star.png", "-16711936")
		// ❌ X - Google caution
		case 0x274C, 0x1F6AB: // ❌ 🚫
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-16776961")
		// ➰ Curly loop - Google trail
		case 0x1F0: // ➰
			return ("a-u-G", "\(googleUUID)/Google/trail.png", "-16776961")
		// ➿ Double curly loop - Google trail
		case 0x1F1F: // ➿
			return ("a-u-G", "\(googleUUID)/Google/trail.png", "-16776961")
			
		// === WEATHER ===
		// 🌤️ Sun behind cloud - Google partly_cloudy
		case 0x1F324: // 🌤️
			return ("a-u-G", "\(googleUUID)/Google/partly_cloudy.png", "-256")
		// 🌧️ Rain - Google rainy
		case 0x1F327: // 🌧️
			return ("a-u-G", "\(googleUUID)/Google/rainy.png", "-16776961")
		// 🌨️ Snow - Google snowflake_simple
		case 0x1F328: // 🌨️
			return ("a-u-G", "\(googleUUID)/Google/snowflake_simple.png", "-1")
		// 🌩️ Lightning - Google caution
		case 0x1F329: // 🌩
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-256")
		// 🌀 Cyclone - Google sunny
		case 0x1F300: // 🌀
			return ("a-u-G", "\(googleUUID)/Google/sunny.png", "-16776961")
		// 🌈 Rainbow - Google star
		case 0x1F308: // 🌈
			return ("a-u-G", "\(googleUUID)/Google/star.png", "-16776961")
		// 🌪️ Tornado - Google caution
		case 0x1F32A: // 🌪️
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-1")
		// 🌋 Volcano - Google volcano
		case 0x1F30B: // 🌋
			return ("a-u-G", "\(googleUUID)/Google/volcano.png", "-16776961")
		// 🏜️ Desert - Google parks
		case 0x1F3DC: // 🏜️
			return ("a-u-G", "\(googleUUID)/Google/parks.png", "-16776961")
		// 🌫️ Fog - Google partly_cloudy
		case 0x1F32B: // 🌫️
			return ("a-u-G", "\(googleUUID)/Google/partly_cloudy.png", "-16776961")
		// 🌬️ Wind - Google partly_cloudy
		case 0x1F32C: // 🌬️
			return ("a-u-G", "\(googleUUID)/Google/partly_cloudy.png", "-16711936")
			
		// === GLOBE ===
		// 🌍 Globe - Generic placemark_circle
		case 0x1F30D, 0x1F30E, 0x1F30F, 0x1F310: // 🌍 🌎 🌏 🌐
			return ("a-u-G", "\(genericUUID)/Shapes/placemark_circle.png", "-16776961")
		// 🗺️ Map - Generic placemark_square
		case 0x1F5FA: // 🗺
			return ("a-u-G", "\(genericUUID)/Shapes/placemark_square.png", "-16776961")
		// 🧭 Compass - Generic compass (use trail)
		case 0x1F6AD: // 🧭
			return ("a-u-G", "\(googleUUID)/Google/trail.png", "-16776961")
			
		// === FOOD ===
		// 🍔 Burger - Google dining
		case 0x1F354: // 🍔
			return ("a-u-G", "\(googleUUID)/Google/dining.png", "-256")
		// 🍕 Pizza - Google dining
		case 0x1F355: // 🍕
			return ("a-u-G", "\(googleUUID)/Google/dining.png", "-256")
		// ☕ Coffee - Google coffee
		case 0x2615: // ☕
			return ("a-u-G", "\(googleUUID)/Google/coffee.png", "-256")
		// 🍺 Beer - Google bars
		case 0x1F37A: // 🍺
			return ("a-u-G", "\(googleUUID)/Google/bars.png", "-256")
		// 🍷 Wine - Google bars
		case 0x1F377: // 🍷
			return ("a-u-G", "\(googleUUID)/Google/bars.png", "-65281")
		// 🥗 Salad - Google dining
		case 0x1F957: // 🥗
			return ("a-u-G", "\(googleUUID)/Google/dining.png", "-16711936")
		// 🍿 Popcorn - Google movies
		case 0x1F37F: // 🍿
			return ("a-u-G", "\(googleUUID)/Google/movies.png", "-16776961")
		// 🍩 Donut - Google donut
		case 0x1F369: // 🍩
			return ("a-u-G", "\(googleUUID)/Google/donut.png", "-16776961")
		// 🍪 Cookie - Google donut
		case 0x1F36A: // 🍪
			return ("a-u-G", "\(googleUUID)/Google/donut.png", "-16776961")
		// 🍫 Chocolate - Google donut
		case 0x1F36B: // 🍫
			return ("a-u-G", "\(googleUUID)/Google/donut.png", "-16776961")
		// 🍬 Candy - Google donut
		case 0x1F36C: // 🍬
			return ("a-u-G", "\(googleUUID)/Google/donut.png", "-16776961")
		// 🍭 Lollipop - Google donut
		case 0x1F36D: // 🍭
			return ("a-u-G", "\(googleUUID)/Google/donut.png", "-16776961")
		// 🍦 Ice Cream - Google donut
		case 0x1F368: // 🍦
			return ("a-u-G", "\(googleUUID)/Google/donut.png", "-16776961")
		// 🥤 Cup - Google coffee
		case 0x1F964: // 🥤
			return ("a-u-G", "\(googleUUID)/Google/coffee.png", "-16776961")
		// 🍵 Tea - Google coffee
		case 0x1F375: // 🍵
			return ("a-u-G", "\(googleUUID)/Google/coffee.png", "-16711936")
		// 🥃 Whiskey - Google bars
		case 0x1F943: // 🥃
			return ("a-u-G", "\(googleUUID)/Google/bars.png", "-16776961")
		// 🥂 Cheers - Google bars
		case 0x1F942: // 🥂
			return ("a-u-G", "\(googleUUID)/Google/bars.png", "-16776961")
		// 🍾 Bottle - Google bars
		case 0x1F37E: // 🍾
			return ("a-u-G", "\(googleUUID)/Google/bars.png", "-16776961")
			
		// === RECREATION ===
		// 🎣 Fishing - Google fishing
		case 0x1F3A3: // 🎣
			return ("a-u-G", "\(googleUUID)/Google/fishing.png", "-16776961")
		// ⛳ Golf - Google golf
		case 0x1F3CC: // ⛳
			return ("a-u-G", "\(googleUUID)/Google/golf.png", "-16711936")
		// ⛷️ Ski - Google ski
		case 0x1F3BF: // ⛷️
			return ("a-u-G", "\(googleUUID)/Google/ski.png", "-16711936")
		// 🏊 Swimming - Google swimming
		case 0x1F3CA: // 🏊
			return ("a-u-G", "\(googleUUID)/Google/swimming.png", "-16776961")
		// 🏄 Surfing - Google swimming
		case 0x1F3C4: // 🏄
			return ("a-u-G", "\(googleUUID)/Google/swimming.png", "-16776961")
		// 🐟 Fish - Google fishing
		case 0x1F41F: // 🐟
			return ("a-u-G", "\(googleUUID)/Google/fishing.png", "-16776961")
		// 🌾 Farm - Google parks
		case 0x1F33E: // 🌾
			return ("a-u-G", "\(googleUUID)/Google/parks.png", "-16711936")
		// 🐄 Farm Animal - Google parks
		case 0x1F404: // 🐄
			return ("a-u-G", "\(googleUUID)/Google/parks.png", "-16711936")
		// 🐕 Dog - Google hiker
		case 0x1F415: // 🐕
			return ("a-u-G", "\(googleUUID)/Google/hiker.png", "-16711936")
		// 🐈 Cat - Google hiker
		case 0x1F431: // 🐈
			return ("a-u-G", "\(googleUUID)/Google/hiker.png", "-16711936")
		// 🐓 Rooster - Google info
		case 0x1F413: // 🐓
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦅 Eagle - Google info
		case 0x1F425: // 🦅
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦋 Butterfly - Google info
		case 0x1F98B: // 🦋
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐝 Bee - Google info
		case 0x1F41D: // 🐝
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐞 Beetle - Google info
		case 0x1F41E: // 🐞
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦀 Crab - Google fishing
		case 0x1F980: // 🦀
			return ("a-u-G", "\(googleUUID)/Google/fishing.png", "-16776961")
		// 🦞 Lobster - Google fishing
		case 0x1F99E: // 🦞
			return ("a-u-G", "\(googleUUID)/Google/fishing.png", "-16776961")
		// 🐚 Shell - Google fishing
		case 0x1F41A: // 🐚
			return ("a-u-G", "\(googleUUID)/Google/fishing.png", "-16776961")
		// 🐙 Octopus - Google fishing
		case 0x1F419: // 🐙
			return ("a-u-G", "\(googleUUID)/Google/fishing.png", "-16776961")
		// 🦑 Squid - Google fishing
		case 0x1F991: // 🦑
			return ("a-u-G", "\(googleUUID)/Google/fishing.png", "-16776961")
		// 🦎 Lizard - Google info
		case 0x1F98E: // 🦎
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐍 Snake - Google info
		case 0x1F40D: // 🐍
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦖 T-Rex - Google info
		case 0x1F996: // 🦖
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦕 Sauropod - Google info
		case 0x1F995: // 🦕
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦈 Shark - Google fishing
		case 0x1F988: // 🦈
			return ("a-u-G", "\(googleUUID)/Google/fishing.png", "-16776961")
		// 🐳 Whale - Google water
		case 0x1F433: // 🐳
			return ("a-u-G", "\(googleUUID)/Google/water.png", "-16776961")
		// 🐬 Dolphin - Google water
		case 0x1F42C: // 🐬
			return ("a-u-G", "\(googleUUID)/Google/water.png", "-16776961")
		// 🐊 Crocodile - Google water
		case 0x1F40A: // 🐊
			return ("a-u-G", "\(googleUUID)/Google/water.png", "-16776961")
		// 🐆 Leopard - Google info
		case 0x1F406: // 🐆
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐅 Tiger - Google info
		case 0x1F405: // 🐅
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐃 Buffalo - Google info
		case 0x1F403: // 🐃
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐂 Ox - Google info
		case 0x1F402: // 🐂
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐎 Horse - Google info
		case 0x1F434: // 🐎
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐏 Ram - Google info
		case 0x1F40F: // 🐏
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐑 Sheep - Google info
		case 0x1F411: // 🐑
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐐 Goat - Google info
		case 0x1F410: // 🐐
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦙 Llama - Google info
		case 0x1F999: // 🦙
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐕‍🦺 Service Dog - Google hiker
		case 0x1F9BA: // 🐕‍🦺
			return ("a-u-G", "\(googleUUID)/Google/hiker.png", "-16776961")
		// 🐩 Poodle - Google hiker
		case 0x1F429: // 🐩
			return ("a-u-G", "\(googleUUID)/Google/hiker.png", "-16776961")
		// 🐈‍⬛ Black Cat - Google hiker
		case 0x1F408: // 🐈‍⬛
			return ("a-u-G", "\(googleUUID)/Google/hiker.png", "-16776961")
		// 🦝 Raccoon - Google info
		case 0x1F99D: // 🦝
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦊 Fox - Google info
		case 0x1F98A: // 🦊
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐻 Bear - Google info
		case 0x1F43B: // 🐻
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐼 Panda - Google info
		case 0x1F43C: // 🐼
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐨 Koala - Google info
		case 0x1F428: // 🐨
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐯 Tiger - Google info
		case 0x1F42F: // 🐯
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦁 Lion - Google info
		case 0x1F981: // 🦁
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐮 Cow - Google info
		case 0x1F42E: // 🐮
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐷 Pig - Google info
		case 0x1F437: // 🐷
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐖 Pig (big) - Google info
		case 0x1F416: // 🐖
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐗 Boar - Google info
		case 0x1F417: // 🐗
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🐘 Elephant - Google info
		case 0x1F418: // 🐘
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦏 Rhino - Google info
		case 0x1F98F: // 🦏
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦛 Hippo - Google info
		case 0x1F99B: // 🦛
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦒 Giraffe - Google info
		case 0x1F992: // 🦒
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦬 Bison - Google info
		case 0x1F9AC: // 🦬
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦣 Mammoth - Google info
		case 0x1F9A3: // 🦣
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦌 Deer - Google info
		case 0x1F98C: // 🦌
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🦌 Moose - Google info
		case 0x1F98D: // 🦌
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
			
		// === INFRASTRUCTURE ===
		// 🚩 Checkpoint - Google flag
		case 0x1F6A6: // 🚩
			return ("a-u-G", "\(googleUUID)/Google/flag.png", "-16776961")
		// ⛔ No Entry - Google caution
		case 0x26D4: // ⛔
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-16776961")
		// 🛑 Stop - Google caution
		case 0x1F6D1: // 🛑
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-16776961")
		// 🏢 Office Building - Google homegardenbusiness
		case 0x1F3E2: // 🏢
			return ("a-u-G", "\(googleUUID)/Google/homegardenbusiness.png", "-16776961")
		// 🏬 Bank - Google info
		case 0x1F3E6: // 🏬
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🏩 Love Hotel - Google lodging
		case 0x1F3E9: // 🏩
			return ("a-u-G", "\(googleUUID)/Google/lodging.png", "-16776961")
		// 🛤️ Railway - Google rail
		case 0x1F6E2: // 🛤️
			return ("a-u-G", "\(googleUUID)/Google/rail.png", "-16711936")
		// 🛣️ Motorway - Google info
		case 0x1F6E3: // 🛣️
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🚎 Trolleybus - Google bus
		case 0x1F68E: // 🚎
			return ("a-u-G", "\(googleUUID)/Google/bus.png", "-16776961")
		// 🚈 Metro - Google rail
		case 0x1F688: // 🚈
			return ("a-u-G", "\(googleUUID)/Google/rail.png", "-16711936")
		// 🚊 Tram - Google tram
		case 0x1F68A: // 🚊
			return ("a-u-G", "\(googleUUID)/Google/tram.png", "-16776961")
		// 🚉 Station - Google rail
		case 0x1F689: // 🚉
			return ("a-u-G", "\(googleUUID)/Google/rail.png", "-16776961")
		// 🛃 Custom - Google info
		case 0x1F6C3: // 🛃
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🛂 Passport control - Google info
		case 0x1F6C2: // 🛂
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🚮 Litter - Google info
		case 0x1F6AE: // 🚮
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
		// 🚰 Water - Google water
		case 0x1F6B0: // 🚰
			return ("a-u-G", "\(googleUUID)/Google/water.png", "-16776961")
		// 🚱 Non-potable - Google caution
		case 0x1F6B1: // 🚱
			return ("a-u-G", "\(googleUUID)/Google/caution.png", "-16776961")
		// ♿ Wheelchair - Google wheel_chair_accessible
		case 0x267F: // ♿
			return ("a-u-G", "\(googleUUID)/Google/wheel_chair_accessible.png", "-16711936")
		// 🚻 Bathroom - Google info
		case 0x1F6BB: // 🚻
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
		// 🚹 Men's - Google info
		case 0x1F6B9: // 🚹
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🚺 Women's - Google info
		case 0x1F6BA: // 🚺
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🚼 Baby - Google info
		case 0x1F6BC: // 🚼
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🚾 Loo - Google info
		case 0x1F6BE: // 🚾
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16776961")
		// 🅿️ Parking - Google info
		case 0x1F17F: // 🅿️
			return ("a-u-G", "\(googleUUID)/Google/info.png", "-16711936")
			
		// === Default - RED pushpin ===
		default:
			return ("a-u-G", "\(genericUUID)/Tacks/red-pushpin.png", "-16776961")
		}
	}
}
