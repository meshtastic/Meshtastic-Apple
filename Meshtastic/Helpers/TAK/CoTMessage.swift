//
//  CoTMessage.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import MeshtasticProtobufs
import CoreLocation

/// Cursor on Target (CoT) message representation
/// Handles both parsing incoming CoT XML and generating outgoing CoT XML
struct CoTMessage: Identifiable, Sendable {
	let id = UUID()

	// MARK: - Core CoT Event Attributes

	/// Unique identifier for this event
	var uid: String

	/// CoT type (e.g., "a-f-G-U-C" for friendly ground unit, "b-t-f" for chat)
	var type: String

	/// Event generation time
	var time: Date

	/// Start of event validity
	var start: Date

	/// When this event becomes stale
	var stale: Date

	/// How the event was generated (e.g., "m-g" for machine GPS, "h-g-i-g-o" for human generated)
	var how: String

	// MARK: - Point Element (Location)

	/// Latitude in degrees
	var latitude: Double

	/// Longitude in degrees
	var longitude: Double

	/// Height above ellipsoid in meters
	var hae: Double

	/// Circular error in meters
	var ce: Double

	/// Linear error in meters
	var le: Double

	// MARK: - Detail Elements

	/// Contact information (callsign, endpoint)
	var contact: CoTContact?

	/// Group/team assignment
	var group: CoTGroup?

	/// Device status (battery)
	var status: CoTStatus?

	/// Movement track (speed, course)
	var track: CoTTrack?

	/// Chat message details
	var chat: CoTChat?

	/// Remarks/comments text
	var remarks: String?

	/// Raw detail XML content for elements we don't explicitly parse
	/// Used to preserve generic CoT elements (colors, shapes, labels, etc.)
	var rawDetailXML: String?

	// MARK: - Initialization

	init(
		uid: String,
		type: String,
		time: Date = Date(),
		start: Date = Date(),
		stale: Date = Date().addingTimeInterval(600),
		how: String = "m-g",
		latitude: Double = 0,
		longitude: Double = 0,
		hae: Double = 9999999.0,
		ce: Double = 9999999.0,
		le: Double = 9999999.0,
		contact: CoTContact? = nil,
		group: CoTGroup? = nil,
		status: CoTStatus? = nil,
		track: CoTTrack? = nil,
		chat: CoTChat? = nil,
		remarks: String? = nil,
		rawDetailXML: String? = nil
	) {
		self.uid = uid
		self.type = type
		self.time = time
		self.start = start
		self.stale = stale
		self.how = how
		self.latitude = latitude
		self.longitude = longitude
		self.hae = hae
		self.ce = ce
		self.le = le
		self.contact = contact
		self.group = group
		self.status = status
		self.track = track
		self.chat = chat
		self.remarks = remarks
		self.rawDetailXML = rawDetailXML
	}

	// MARK: - Factory Methods

	/// Create a PLI (Position Location Information) message for a friendly ground unit
	static func pli(
		uid: String,
		callsign: String,
		latitude: Double,
		longitude: Double,
		altitude: Double = 9999999.0,
		speed: Double = 0,
		course: Double = 0,
		team: String = "Cyan",
		role: String = "Team Member",
		battery: Int = 100,
		staleMinutes: Int = 10
	) -> CoTMessage {
		let now = Date()
		return CoTMessage(
			uid: uid,
			type: "a-f-G-U-C",
			time: now,
			start: now,
			stale: now.addingTimeInterval(TimeInterval(staleMinutes * 60)),
			how: "m-g",
			latitude: latitude,
			longitude: longitude,
			hae: altitude,
			ce: 9999999.0,
			le: 9999999.0,
			contact: CoTContact(callsign: callsign, endpoint: "0.0.0.0:4242:tcp"),
			group: CoTGroup(name: team, role: role),
			status: CoTStatus(battery: battery),
			track: CoTTrack(speed: speed, course: course)
		)
	}

	/// Create a chat message (b-t-f type for outgoing)
	static func chat(
		senderUid: String,
		senderCallsign: String,
		message: String,
		chatroom: String = "All Chat Rooms"
	) -> CoTMessage {
		let now = Date()
		let messageId = UUID().uuidString
		return CoTMessage(
			uid: "GeoChat.\(senderUid).\(chatroom).\(messageId)",
			type: "b-t-f",
			time: now,
			start: now,
			stale: now.addingTimeInterval(86400),
			how: "h-g-i-g-o",
			latitude: 0,
			longitude: 0,
			hae: 9999999.0,
			ce: 9999999.0,
			le: 9999999.0,
			chat: CoTChat(
				message: message,
				senderCallsign: senderCallsign,
				chatroom: chatroom
			),
			remarks: message
		)
	}

	// MARK: - Create from Meshtastic TAKPacket

	/// Convert Meshtastic TAKPacket protobuf to CoT message
	static func fromTAKPacket(_ takPacket: TAKPacket, deviceUid: String? = nil) -> CoTMessage? {
		let currentDate = Date()
		let staleDate = currentDate.addingTimeInterval(10 * 60) // 10 minute stale

		// Handle PLI (Position Location Information)
		if case .pli(let pli) = takPacket.payloadVariant {
			// Validate we have required fields
			guard takPacket.hasContact,
				  pli.latitudeI != 0 || pli.longitudeI != 0 else {
				return nil
			}

			// Parse device_callsign in case it contains smuggled messageId (shouldn't for PLI, but be safe)
			let (actualDeviceCallsign, _) = TAKMeshtasticBridge.parseDeviceCallsign(takPacket.contact.deviceCallsign)
			let uid = actualDeviceCallsign.isEmpty
				? (deviceUid ?? UUID().uuidString)
				: actualDeviceCallsign

			return CoTMessage(
				uid: uid,
				type: "a-f-G-U-C",
				time: currentDate,
				start: currentDate,
				stale: staleDate,
				how: "m-g",
				latitude: Double(pli.latitudeI) * 1e-7,
				longitude: Double(pli.longitudeI) * 1e-7,
				hae: Double(pli.altitude),
				ce: 9999999.0,
				le: 9999999.0,
				contact: CoTContact(
					callsign: takPacket.contact.callsign,
					endpoint: "0.0.0.0:4242:tcp"
				),
				group: takPacket.hasGroup ? CoTGroup(
					name: takPacket.group.team.cotColorName,
					role: takPacket.group.role.cotRoleName
				) : CoTGroup(name: "Cyan", role: "Team Member"),
				status: takPacket.hasStatus ? CoTStatus(
					battery: Int(takPacket.status.battery)
				) : nil,
				track: CoTTrack(
					speed: Double(pli.speed),
					course: Double(pli.course)
				)
			)
		}

		// Handle GeoChat
		if case .chat(let geoChat) = takPacket.payloadVariant {
			// Parse device_callsign which may contain smuggled messageId
			// Format: "<actual_device_callsign>|<messageId>" or just "<actual_device_callsign>"
			let rawDeviceCallsign = takPacket.hasContact ? takPacket.contact.deviceCallsign : ""
			let (actualDeviceCallsign, smuggledMessageId) = TAKMeshtasticBridge.parseDeviceCallsign(rawDeviceCallsign)

			let uid = actualDeviceCallsign.isEmpty
				? (deviceUid ?? UUID().uuidString)
				: actualDeviceCallsign

			let chatroom = geoChat.hasTo ? geoChat.to : "All Chat Rooms"
			// Use smuggled messageId if present, otherwise generate new one
			let messageId = smuggledMessageId ?? UUID().uuidString

			return CoTMessage(
				uid: "GeoChat.\(uid).\(chatroom).\(messageId)",
				type: "b-t-f",
				time: currentDate,
				start: currentDate,
				stale: currentDate.addingTimeInterval(86400),
				how: "h-g-i-g-o",
				latitude: 0,
				longitude: 0,
				hae: 9999999.0,
				ce: 9999999.0,
				le: 9999999.0,
				contact: takPacket.hasContact ? CoTContact(
					callsign: takPacket.contact.callsign,
					endpoint: "0.0.0.0:4242:tcp"
				) : nil,
				chat: CoTChat(
					message: geoChat.message,
					senderCallsign: takPacket.hasContact ? takPacket.contact.callsign : nil,
					chatroom: chatroom
				),
				remarks: geoChat.message
			)
		}

		return nil
	}

	// MARK: - XML Generation

	/// Generate CoT XML string for transmission to TAK clients
	func toXML() -> String {
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

		var cot = "<?xml version='1.0' encoding='UTF-8' standalone='yes'?>"
		cot += "<event version='2.0' uid='\(uid.xmlEscaped)' "
		cot += "type='\(type)' "
		cot += "time='\(dateFormatter.string(from: time))' "
		cot += "start='\(dateFormatter.string(from: start))' "
		cot += "stale='\(dateFormatter.string(from: stale))' "
		cot += "how='\(how)'>"
		cot += "<point lat='\(latitude)' lon='\(longitude)' "
		cot += "hae='\(hae)' ce='\(ce)' le='\(le)'/>"
		cot += "<detail>"

		// Contact element
		if let contact {
			cot += "<contact endpoint='\(contact.endpoint ?? "0.0.0.0:4242:tcp")' "
			cot += "callsign='\(contact.callsign.xmlEscaped)'/>"
			cot += "<uid Droid='\(contact.callsign.xmlEscaped)'/>"
		}

		// Group element
		if let group {
			cot += "<__group role='\(group.role.xmlEscaped)' name='\(group.name.xmlEscaped)'/>"
		}

		// Status element
		if let status {
			cot += "<status battery='\(status.battery)'/>"
		}

		// Track element
		if let track {
			cot += "<track course='\(track.course)' speed='\(track.speed)'/>"
		}

		// Chat elements (for b-t-f messages)
		if let chat {
			// Derive sender UID and messageId from GeoChat UID when possible, with safe fallbacks
			let senderUid: String
			let messageId: String

			if uid.hasPrefix("GeoChat.") {
				let components = uid.split(separator: ".")
				if components.count >= 3 {
					// Expected GeoChat format: GeoChat.<senderUid>.<messageId>
					senderUid = String(components[1])
					messageId = String(components[2])
				} else {
					// Malformed GeoChat UID; fall back safely
					senderUid = uid
					messageId = uid
				}
			} else {
				// Non-GeoChat UID; use uid as both sender and stable message identifier
				senderUid = uid
				messageId = uid
			}
			cot += "<__chat parent='RootContactGroup' groupOwner='false' "
			cot += "messageId='\(messageId)' "
			cot += "chatroom='\(chat.chatroom.xmlEscaped)' id='\(chat.chatroom.xmlEscaped)' "
			cot += "senderCallsign='\(chat.senderCallsign?.xmlEscaped ?? "")'>"
			cot += "<chatgrp uid0='\(senderUid.xmlEscaped)' "
			cot += "uid1='\(chat.chatroom.xmlEscaped)' id='\(chat.chatroom.xmlEscaped)'/>"
			cot += "</__chat>"
			cot += "<link uid='\(senderUid.xmlEscaped)' type='a-f-G-U-C' relation='p-p'/>"
			cot += "<__serverdestination destinations='0.0.0.0:4242:tcp:\(senderUid.xmlEscaped)'/>"
			cot += "<remarks source='BAO.F.ATAK.\(senderUid.xmlEscaped)' "
			cot += "to='\(chat.chatroom.xmlEscaped)' "
			cot += "time='\(dateFormatter.string(from: time))'>"
			cot += "\(chat.message.xmlEscaped)</remarks>"
		} else if let remarks, !remarks.isEmpty {
			cot += "<remarks>\(remarks.xmlEscaped)</remarks>"
		}

		// Include raw detail XML for generic CoT elements (colors, shapes, labels, etc.)
		// This preserves elements we don't explicitly parse
		if let rawDetailXML, !rawDetailXML.isEmpty {
			cot += rawDetailXML
		}

		cot += "</detail></event>"

		return cot
	}
}

// MARK: - Supporting Types

/// Contact information for a CoT event
struct CoTContact: Sendable, Equatable {
	var callsign: String
	var endpoint: String?
	var phone: String?

	init(callsign: String, endpoint: String? = nil, phone: String? = nil) {
		self.callsign = callsign
		self.endpoint = endpoint
		self.phone = phone
	}
}

/// Group/team assignment for a CoT event
struct CoTGroup: Sendable, Equatable {
	/// Team color name (e.g., "Cyan", "Green", "Red")
	var name: String
	/// Role name (e.g., "Team Member", "Team Lead")
	var role: String

	init(name: String, role: String) {
		self.name = name
		self.role = role
	}
}

/// Device status for a CoT event
struct CoTStatus: Sendable, Equatable {
	var battery: Int

	init(battery: Int) {
		self.battery = battery
	}
}

/// Movement track for a CoT event
struct CoTTrack: Sendable, Equatable {
	var speed: Double
	var course: Double

	init(speed: Double, course: Double) {
		self.speed = speed
		self.course = course
	}
}

/// Chat message details for a CoT event
struct CoTChat: Sendable, Equatable {
	var message: String
	var senderCallsign: String?
	var chatroom: String

	init(message: String, senderCallsign: String? = nil, chatroom: String = "All Chat Rooms") {
		self.message = message
		self.senderCallsign = senderCallsign
		self.chatroom = chatroom
	}
}

// MARK: - String Extension for XML Escaping

extension String {
	/// Escape special XML characters
	var xmlEscaped: String {
		self.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "'", with: "&apos;")
	}
}

// MARK: - Team/Role Extensions for Meshtastic Protobufs

extension Team {
	/// Convert Meshtastic Team enum to CoT color name
	var cotColorName: String {
		switch self {
		case .white: return "White"
		case .yellow: return "Yellow"
		case .orange: return "Orange"
		case .magenta: return "Magenta"
		case .red: return "Red"
		case .maroon: return "Maroon"
		case .purple: return "Purple"
		case .darkBlue: return "Dark Blue"
		case .blue: return "Blue"
		case .cyan: return "Cyan"
		case .teal: return "Teal"
		case .green: return "Green"
		case .darkGreen: return "Dark Green"
		case .brown: return "Brown"
		case .unspecifedColor: return "Cyan"
		case .UNRECOGNIZED: return "Cyan"
		}
	}

	/// Create Team from CoT color name
	static func fromColorName(_ name: String) -> Team {
		switch name.lowercased() {
		case "white": return .white
		case "yellow": return .yellow
		case "orange": return .orange
		case "magenta": return .magenta
		case "red": return .red
		case "maroon": return .maroon
		case "purple": return .purple
		case "dark blue", "darkblue": return .darkBlue
		case "blue": return .blue
		case "cyan": return .cyan
		case "teal": return .teal
		case "green": return .green
		case "dark green", "darkgreen": return .darkGreen
		case "brown": return .brown
		default: return .cyan
		}
	}
}

extension MemberRole {
	/// Convert Meshtastic MemberRole enum to CoT role name
	var cotRoleName: String {
		switch self {
		case .teamMember: return "Team Member"
		case .teamLead: return "Team Lead"
		case .hq: return "HQ"
		case .sniper: return "Sniper"
		case .medic: return "Medic"
		case .forwardObserver: return "Forward Observer"
		case .rto: return "RTO"
		case .k9: return "K9"
		case .unspecifed: return "Team Member"
		case .UNRECOGNIZED: return "Team Member"
		}
	}

	/// Create MemberRole from CoT role name
	static func fromRoleName(_ name: String) -> MemberRole {
		switch name.lowercased() {
		case "team member": return .teamMember
		case "team lead": return .teamLead
		case "hq", "headquarters": return .hq
		case "sniper": return .sniper
		case "medic": return .medic
		case "forward observer": return .forwardObserver
		case "rto": return .rto
		case "k9": return .k9
		default: return .teamMember
		}
	}
}

// MARK: - XML Parsing

extension CoTMessage {
	/// Parse a CoT XML string into a CoTMessage
	/// - Parameter xml: The CoT XML string
	/// - Returns: Parsed CoTMessage, or nil if parsing failed
	static func parse(from xml: String) -> CoTMessage? {
		guard let data = xml.data(using: .utf8) else {
			return nil
		}

		// Use the existing CoTXMLParser class
		let parser = CoTXMLParser(data: data)
		do {
			return try parser.parse()
		} catch {
			return nil
		}
	}
}
