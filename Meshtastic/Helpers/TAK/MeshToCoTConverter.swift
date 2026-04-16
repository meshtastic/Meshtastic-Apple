//
//  MeshToCoTConverter.swift
//  Meshtastic
//
//  Converts Meshtastic packets to CoT format for TAK Server
//

import Foundation
import MeshtasticProtobufs
import CoreLocation
import OSLog
import Combine

/// Converts Meshtastic packets to CoT format for bridging to TAK Server
final class MeshToCoTConverter: ObservableObject {
	
	static let shared = MeshToCoTConverter()
	
	private let logger = Logger(subsystem: "Meshtastic", category: "MeshToCoT")
	
	private init() {}
	
	// MARK: - Position	// MARK: Packet to CoT
	
	/// Convert a Meshtastic position packet to CoT message
	func convertPosition(_ position: Position, from node: NodeInfoEntity) -> CoTMessage? {
		guard let user = node.user else {
			logger.warning("Cannot convert position: node has no user info")
			return nil
		}
		
		let callsign = user.longName ?? user.shortName ?? "Unknown"
		let uid = "MESHTASTIC-\(node.num.toHex())"
		
		let latitude = Double(position.latitudeI) / 1e7
		let longitude = Double(position.longitudeI) / 1e7
		let altitude = Double(position.altitude)
		
		var speed: Double = 0
		var course: Double = 0
		if position.speed != 0 {
			speed = Double(position.speed) * 0.194384 // Convert to knots
		}
		if position.heading != 0 {
			course = Double(position.heading)
		}
		
		let battery = Int(position.batteryLevel)
		
		return CoTMessage.pli(
			uid: uid,
			callsign: callsign,
			latitude: latitude,
			longitude: longitude,
			altitude: altitude,
			speed: speed,
			course: course,
			team: "Meshtastic",
			role: "Team Member",
			battery: battery > 0 ? battery : 100,
			staleMinutes: 10
		)
	}
	
	// MARK: - Node Info to CoT
	
	/// Convert node info to CoT message (for node presence updates)
	func convertNodeInfo(_ node: NodeInfoEntity) -> CoTMessage? {
		guard let user = node.user else {
			logger.warning("Cannot convert node info: node has no user info")
			return nil
		}
		
		let callsign = user.longName ?? user.shortName ?? "Unknown"
		let uid = "MESHTASTIC-\(node.num.toHex())"
		
		var latitude = 0.0
		var longitude = 0.0
		var altitude = 9999999.0
		
		if let position = node.position {
			latitude = Double(position.latitudeI) / 1e7
			longitude = Double(position.longitudeI) / 1e7
			if position.altitude != 0 {
				altitude = Double(position.altitude)
			}
		}
		
		// Determine CoT type based on device role
		let cotType = getCoTTypeForRole(user.role)
		
		let now = Date()
		return CoTMessage(
			uid: uid,
			type: cotType,
			time: now,
			start: now,
			stale: now.addingTimeInterval(3600), // 1 hour stale for node info
			how: "m-g",
			latitude: latitude,
			longitude: longitude,
			hae: altitude,
			ce: 9999999.0,
			le: 9999999.0,
			contact: CoTContact(callsign: callsign, endpoint: "0.0.0.0:4242:tcp"),
			group: CoTGroup(name: "Meshtastic", role: getRoleNameForDeviceRole(user.role)),
			remarks: "Meshtastic Node: \(callsign)"
		)
	}
	
	// MARK: - Waypoint to CoT
	
	/// Convert a Meshtastic waypoint to CoT message
	func convertWaypoint(_ waypoint: Waypoint, from node: NodeInfoEntity?) -> CoTMessage? {
		let uid = "WAYPOINT-\(waypoint.id)"
		
		let latitude = Double(waypoint.latitudeI) / 1e7
		let longitude = Double(waypoint.longitudeI) / 1e7
		let altitude = waypoint.altitude > 0 ? Double(waypoint.altitude) : 9999999.0
		
		let name = waypoint.name.isEmpty ? "Unnamed Waypoint" : waypoint.name
		let description = waypoint.description_p.isEmpty ? "Meshtastic Waypoint" : waypoint.description_p
		
		// Get emoji based on waypoint icon/expire time
		let iconEmoji = getEmojiForWaypoint(waypoint)
		
		// Handle expiry - if expire is 0, never expire. Otherwise use the expire time as Unix timestamp
		let stale: Date
		if waypoint.expire == 0 {
			// Never expire - set to 1 year from now
			stale = Date().addingTimeInterval(365 * 24 * 60 * 60)
		} else {
			// expire is Unix timestamp when waypoint expires
			let expireDate = Date(timeIntervalSince1970: TimeInterval(waypoint.expire))
			if expireDate > Date() {
				stale = expireDate
			} else {
				// Already expired, don't broadcast
				return nil
			}
		}
		
		return CoTMessage(
			uid: uid,
			type: "b-ttf-ff", // Point feature friend - standard CoT type for waypoints/markers
			time: Date(),
			start: Date(),
			stale: stale,
			how: "m-g",
			latitude: latitude,
			longitude: longitude,
			hae: altitude,
			ce: 100.0,
			le: 100.0,
			contact: CoTContact(callsign: "\(iconEmoji) \(name)", endpoint: "0.0.0.0:4242:tcp"),
			remarks: "\(description)\nCreated by: \(node?.user?.longName ?? "Unknown")"
		)
	}
	
	// MARK: - Text Message to CoT
	
	/// Convert a Meshtastic text message to CoT chat message
	func convertTextMessage(_ message: MessageEntity, from sender: NodeInfoEntity) -> CoTMessage? {
		guard let user = sender.user,
			  let text = message.text else {
			return nil
		}
		
		let senderName = user.longName ?? user.shortName ?? "Unknown"
		let senderUid = "MESHTASTIC-\(sender.num.toHex())"
		let messageId = "MSG-\(message.id)"
		
		return CoTMessage.chat(
			senderUid: senderUid,
			senderCallsign: senderName,
			message: text,
			chatroom: "Primary"
		)
	}
	
	// MARK: - Helper Methods
	
	/// Get CoT type based on device role
	private func getCoTTypeForRole(_ role: UInt32) -> String {
		switch DeviceRoles(rawValue: Int(role)) {
		case .router, .routerLate:
			return "a-f-G-E" // Group entity (router)
		case .tracker:
			return "a-f-G-T-C" // Ground unit tracker
		case .tak:
			return "a-f-G-U-C" // TAK client
		case .takTracker:
			return "a-f-G-T-C" // TAK tracker
		case .sensor:
			return "a-f-G-s" // Sensor with friendly affiliation
		case .client, .clientMute, .clientHidden, .lostAndFound:
			return "a-f-G-U-C" // Friendly ground unit
		default:
			return "a-f-G-U-C" // Default to friendly unit
		}
	}
	
	/// Get role name for device role
	private func getRoleNameForDeviceRole(_ role: UInt32) -> String {
		switch DeviceRoles(rawValue: Int(role)) {
		case .router, .routerLate:
			return "Router"
		case .tracker:
			return "Tracker"
		case .tak:
			return "TAK"
		case .takTracker:
			return "TAK Tracker"
		case .sensor:
			return "Sensor"
		case .client:
			return "Client"
		case .clientMute:
			return "Muted"
		case .clientHidden:
			return "Hidden"
		default:
			return "User"
		}
	}
	
	/// Get emoji for waypoint based on icon
	private func getEmojiForWaypoint(_ waypoint: Waypoint) -> String {
		// Use icon field if available, otherwise use expire time to guess
		if waypoint.icon != 0 {
			switch waypoint.icon {
			case 1: return "📍" // Marker
			case 2: return "🚗" // Car
			case 3: return "🚶" // Person
			case 4: return "🏠" // Home
			case 5: return "⛺" // Camp
			case 6: return "⚠️" // Warning
			case 7: return "🏁" // Flag
			case 8: return "🔍" // Search
			case 9: return "🏥" // Medical
			case 10: return "🔥" // Fire
			case 11: return "🚁" // Helicopter
			case 12: return "⛵" // Boat
			case 13: return "🛸" // UFO
			default: return "📍"
			}
		}
		
		// Fallback based on name
		let name = waypoint.name.lowercased()
		if name.contains("help") || name.contains("emergency") {
			return "🆘"
		} else if name.contains("medical") || name.contains("hospital") {
			return "🏥"
		} else if name.contains("danger") || name.contains("warning") {
			return "⚠️"
		} else if name.contains("camp") {
			return "⛺"
		} else if name.contains("home") || name.contains("house") {
			return "🏠"
		} else if name.contains("car") || name.contains("vehicle") {
			return "🚗"
		} else if name.contains("flag") {
			return "🏁"
		} else if name.contains("person") || name.contains("me") {
			return "🚶"
		} else {
			return "📍"
		}
	}
}
