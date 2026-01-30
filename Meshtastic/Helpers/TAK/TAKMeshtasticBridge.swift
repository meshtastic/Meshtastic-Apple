//
//  TAKMeshtasticBridge.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import MeshtasticProtobufs
import OSLog
import CoreData

/// Bridges CoT messages between TAK clients and the Meshtastic mesh network
/// Handles bidirectional conversion and message routing
@MainActor
final class TAKMeshtasticBridge {

	weak var accessoryManager: AccessoryManager?
	weak var takServerManager: TAKServerManager?

	/// Core Data context for node lookups
	var context: NSManagedObjectContext?

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
		guard let accessoryManager else {
			Logger.tak.warning("Cannot send to mesh: AccessoryManager not available")
			return
		}

		guard accessoryManager.isConnected else {
			Logger.tak.warning("Cannot send to mesh: Not connected to Meshtastic device")
			return
		}

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
				try await accessoryManager.sendTAKPacket(takPacket)
				Logger.tak.info("Sent TAKPacket to mesh: \(cotMessage.type)")
			} catch {
				Logger.tak.error("Failed to send TAKPacket to mesh: \(error.localizedDescription)")
			}

		case .exiDirect, .exiFountain:
			// Use EXI compression on ATAK_FORWARDER port (257)
			GenericCoTHandler.shared.accessoryManager = accessoryManager
			do {
				try await GenericCoTHandler.shared.sendGenericCoT(cotMessage)
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
		let callsign = node.user?.shortName ?? node.user?.longName ?? "MESH-\(node.num)"

		// Get battery level from device metrics
		let battery = Int(node.latestDeviceMetrics?.batteryLevel ?? 100)

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
			staleMinutes: 15  // Meshtastic positions can be older
		)
	}

	// MARK: - Broadcast All Mesh Nodes to TAK

	/// Send all known mesh node positions to TAK clients
	/// Useful when a new TAK client connects
	func broadcastAllNodesToTAK() async {
		guard let takServerManager, takServerManager.isRunning else { return }
		guard let context else { return }

		let fetchRequest: NSFetchRequest<NodeInfoEntity> = NodeInfoEntity.fetchRequest()
		// Only nodes with valid positions
		fetchRequest.predicate = NSPredicate(format: "latestPosition != nil")

		do {
			let nodes = try context.fetch(fetchRequest)

			for node in nodes {
				if let cotMessage = createCoTFromNode(node) {
					await takServerManager.broadcast(cotMessage)
				}
			}

			Logger.tak.info("Broadcast \(nodes.count) mesh node positions to TAK clients")
		} catch {
			Logger.tak.error("Failed to fetch nodes for TAK broadcast: \(error.localizedDescription)")
		}
	}

	// MARK: - Helper Methods

	private func lookupNodeInfo(nodeNum: UInt32) -> NodeInfoEntity? {
		guard let context else { return nil }

		let fetchRequest: NSFetchRequest<NodeInfoEntity> = NodeInfoEntity.fetchRequest()
		fetchRequest.predicate = NSPredicate(format: "num == %d", Int64(nodeNum))
		fetchRequest.fetchLimit = 1

		do {
			return try context.fetch(fetchRequest).first
		} catch {
			Logger.tak.warning("Failed to lookup node info for \(nodeNum): \(error.localizedDescription)")
			return nil
		}
	}
}
