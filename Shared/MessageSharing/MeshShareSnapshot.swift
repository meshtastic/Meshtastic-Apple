//
//  MeshShareSnapshot.swift
//  Meshtastic
//

import Foundation

struct MeshShareSnapshot: Codable, Equatable, Sendable {
	static let currentVersion = 1

	let version: Int
	let radioNodeNum: UInt32
	let radioLongName: String
	let radioShortName: String
	let contactURL: String
	let loraConfigData: Data
	let channels: [MeshShareChannel]
	let refreshedAt: Date

	init(
		version: Int = currentVersion,
		radioNodeNum: UInt32,
		radioLongName: String,
		radioShortName: String,
		contactURL: String,
		loraConfigData: Data,
		channels: [MeshShareChannel],
		refreshedAt: Date
	) {
		self.version = version
		self.radioNodeNum = radioNodeNum
		self.radioLongName = radioLongName
		self.radioShortName = radioShortName
		self.contactURL = contactURL
		self.loraConfigData = loraConfigData
		self.channels = channels
		self.refreshedAt = refreshedAt
	}

	func isStale(at date: Date = .now) -> Bool {
		date.timeIntervalSince(refreshedAt) > 30 * 86_400
	}

	var contactReplyURL: String {
		guard var components = URLComponents(string: contactURL) else {
			return contactURL
		}
		components.queryItems = components.queryItems?.filter {
			$0.name.caseInsensitiveCompare("exchange") != .orderedSame
		}
		if components.queryItems?.isEmpty == true {
			components.queryItems = nil
		}
		return components.string ?? contactURL
	}
}

struct MeshShareChannel: Codable, Equatable, Identifiable, Sendable {
	var id: Int32 { index }

	let index: Int32
	let name: String
	let isEncrypted: Bool
	let settingsData: Data
}

enum MeshChannelImportMode: String, Codable, Sendable {
	case replace
	case add
}
