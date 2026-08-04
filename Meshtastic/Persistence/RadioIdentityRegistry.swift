// RadioIdentityRegistry.swift
// Meshtastic

import Foundation
import SwiftData

struct RadioIdentityObservation: Equatable {
	let transport: TransportType
	let transportDeviceID: UUID
	let identifier: String
	let deviceID: String
	let nodeNum: Int64?
	let observedAt: Date

	init(
		transport: TransportType,
		transportDeviceID: UUID,
		identifier: String,
		deviceID: String,
		nodeNum: Int64?,
		observedAt: Date = .now
	) {
		self.transport = transport
		self.transportDeviceID = transportDeviceID
		self.identifier = identifier
		self.deviceID = deviceID
		self.nodeNum = nodeNum
		self.observedAt = observedAt
	}

	var aliasKey: String {
		switch transport {
		case .ble:
			"ble:\(transportDeviceID.uuidString.lowercased())"
		case .tcp:
			"tcp:\(Self.normalizedTCPEndpoint(identifier))"
		case .serial:
			"serial:\(identifier.trimmingCharacters(in: .whitespacesAndNewlines))"
		}
	}

	static func normalizedDeviceID(_ deviceID: String) -> String? {
		let normalized = deviceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard (16...64).contains(normalized.count),
		      normalized != "unknown",
		      normalized.allSatisfy(\.isHexDigit) else { return nil }
		return normalized
	}

	static func normalizedDeviceID(_ data: Data) -> String? {
		guard !data.isEmpty else { return nil }
		if let string = String(data: data, encoding: .utf8),
		   let normalized = normalizedDeviceID(string) {
			return normalized
		}
		return normalizedDeviceID(data.map { String(format: "%02x", $0) }.joined())
	}

	private static func normalizedTCPEndpoint(_ identifier: String) -> String {
		let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
		if let components = URLComponents(string: "//\(trimmed)"),
		   var host = components.host?.lowercased(),
		   !host.isEmpty {
			if host.hasSuffix(".") {
				host.removeLast()
			}
			return "\(host):\(components.port ?? 4403)"
		}
		return trimmed.lowercased()
	}
}

enum RadioIdentityResolution: Equatable {
	case resolved(UUID)
	case quarantined([UUID])
	case ignored
}

@MainActor
final class RadioIdentityRegistry {
	private let container: ModelContainer
	private let context: ModelContext

	init(container: ModelContainer) throws {
		self.container = container
		context = container.mainContext
		context.autosaveEnabled = false
	}

	func record(_ observation: RadioIdentityObservation) throws -> RadioIdentityResolution {
		let deviceID = RadioIdentityObservation.normalizedDeviceID(observation.deviceID)
		let nodeNum = observation.nodeNum.flatMap { $0 > 0 ? $0 : nil }
		guard deviceID != nil || nodeNum != nil else { return .ignored }

		let alias = try alias(for: observation.aliasKey)
		let aliasProfile = alias?.profile
		let deviceProfiles = try profiles(deviceID: deviceID)
		let nodeProfiles = try profiles(nodeNum: nodeNum)

		if deviceProfiles.count > 1 || nodeProfiles.count > 1 {
			return try quarantine(
				profiles: deviceProfiles + nodeProfiles + [aliasProfile].compactMap { $0 },
				observation: observation,
				reason: "Duplicate identity claims"
			)
		}

		if let deviceProfile = deviceProfiles.first {
			let conflicts = nodeProfiles.filter { $0 !== deviceProfile }
				+ [aliasProfile].compactMap { $0 }.filter { $0 !== deviceProfile }
			guard conflicts.isEmpty else {
				return try quarantine(
					profiles: [deviceProfile] + conflicts,
					observation: observation,
					reason: "Device and node claims disagree"
				)
			}
			update(deviceProfile, deviceID: deviceID, nodeNum: nodeNum, at: observation.observedAt)
			try attach(observation, existingAlias: alias, to: deviceProfile)
			try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
			return .resolved(deviceProfile.id)
		}

		if let deviceID {
			if let aliasProfile {
				guard observation.transport == .ble else {
					let newProfile = createDetachedProfile(
						deviceID: deviceID,
						nodeNum: nodeNum,
						at: observation.observedAt
					)
					return try quarantine(
						profiles: [aliasProfile, newProfile],
						observation: nil,
						reason: "Reassignable alias cannot corroborate node fallback"
					)
				}
				let nodeAgrees = nodeNum == nil || aliasProfile.nodeNum == nil || aliasProfile.nodeNum == nodeNum
				let nodeClaimAgrees = nodeProfiles.allSatisfy { $0 === aliasProfile }
				guard aliasProfile.deviceID == nil, nodeAgrees, nodeClaimAgrees else {
					return try quarantine(
						profiles: [aliasProfile] + nodeProfiles,
						observation: observation,
						reason: "Alias promotion conflicts with existing identity"
					)
				}
				update(aliasProfile, deviceID: deviceID, nodeNum: nodeNum, at: observation.observedAt)
				try attach(observation, existingAlias: alias, to: aliasProfile)
				try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
				return .resolved(aliasProfile.id)
			}

			if let nodeProfile = nodeProfiles.first {
				let newProfile = createProfile(
					deviceID: deviceID,
					nodeNum: nodeNum,
					observation: observation
				)
				return try quarantine(
					profiles: [nodeProfile, newProfile],
					observation: nil,
					reason: "Device identity lacks alias evidence for node fallback"
				)
			}

			let profile = createProfile(deviceID: deviceID, nodeNum: nodeNum, observation: observation)
			try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
			return .resolved(profile.id)
		}

		if let aliasProfile {
			let nodeAgrees = nodeNum == nil || aliasProfile.nodeNum == nil || aliasProfile.nodeNum == nodeNum
			guard nodeAgrees, nodeProfiles.allSatisfy({ $0 === aliasProfile }) else {
				return try quarantine(
					profiles: [aliasProfile] + nodeProfiles,
					observation: observation,
					reason: "Alias and node claims disagree"
				)
			}
			update(aliasProfile, deviceID: nil, nodeNum: nodeNum, at: observation.observedAt)
			try attach(observation, existingAlias: alias, to: aliasProfile)
			try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
			return .resolved(aliasProfile.id)
		}

		if let nodeProfile = nodeProfiles.first {
			update(nodeProfile, deviceID: nil, nodeNum: nodeNum, at: observation.observedAt)
			try attach(observation, existingAlias: alias, to: nodeProfile)
			try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
			return .resolved(nodeProfile.id)
		}

		let profile = createProfile(deviceID: nil, nodeNum: nodeNum, observation: observation)
		try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
		return .resolved(profile.id)
	}

	func profiles() throws -> [RadioProfileEntity] {
		try context.fetch(FetchDescriptor<RadioProfileEntity>())
			.sorted { $0.id.uuidString < $1.id.uuidString }
	}

	func aliases() throws -> [RadioTransportAliasEntity] {
		try context.fetch(FetchDescriptor<RadioTransportAliasEntity>())
			.sorted { $0.key < $1.key }
	}

	private func profiles(deviceID: String?) throws -> [RadioProfileEntity] {
		guard let deviceID else { return [] }
		return try profiles().filter { $0.deviceID == deviceID }
	}

	private func profiles(nodeNum: Int64?) throws -> [RadioProfileEntity] {
		guard let nodeNum else { return [] }
		return try profiles().filter { $0.nodeNum == nodeNum }
	}

	private func alias(for key: String) throws -> RadioTransportAliasEntity? {
		try aliases().first { $0.key == key }
	}

	private func createProfile(
		deviceID: String?,
		nodeNum: Int64?,
		observation: RadioIdentityObservation
	) -> RadioProfileEntity {
		let profile = createDetachedProfile(
			deviceID: deviceID,
			nodeNum: nodeNum,
			at: observation.observedAt
		)
		let alias = makeAlias(observation)
		alias.profile = profile
		context.insert(alias)
		return profile
	}

	private func createDetachedProfile(
		deviceID: String?,
		nodeNum: Int64?,
		at date: Date
	) -> RadioProfileEntity {
		let profile = RadioProfileEntity(
			deviceID: deviceID,
			nodeNum: nodeNum,
			createdAt: date,
			lastSeenAt: date
		)
		context.insert(profile)
		return profile
	}

	private func attach(
		_ observation: RadioIdentityObservation,
		existingAlias: RadioTransportAliasEntity?,
		to profile: RadioProfileEntity
	) throws {
		let alias = existingAlias ?? makeAlias(observation)
		alias.transport = observation.transport.rawValue
		alias.identifier = observation.identifier
		alias.transportDeviceID = observation.transportDeviceID
		alias.lastSeenAt = observation.observedAt
		alias.profile = profile
		if existingAlias == nil {
			context.insert(alias)
		}
	}

	private func makeAlias(_ observation: RadioIdentityObservation) -> RadioTransportAliasEntity {
		RadioTransportAliasEntity(
			key: observation.aliasKey,
			transport: observation.transport.rawValue,
			identifier: observation.identifier,
			transportDeviceID: observation.transportDeviceID,
			firstSeenAt: observation.observedAt,
			lastSeenAt: observation.observedAt
		)
	}

	private func update(
		_ profile: RadioProfileEntity,
		deviceID: String?,
		nodeNum: Int64?,
		at date: Date
	) {
		if let deviceID {
			profile.deviceID = deviceID
		}
		if let nodeNum {
			profile.nodeNum = nodeNum
		}
		profile.lastSeenAt = date
	}

	private func quarantine(
		profiles: [RadioProfileEntity],
		observation: RadioIdentityObservation?,
		reason: String
	) throws -> RadioIdentityResolution {
		var uniqueProfiles: [UUID: RadioProfileEntity] = [:]
		for profile in profiles {
			uniqueProfiles[profile.id] = profile
			profile.quarantineReason = reason
		}
		if let observation, try alias(for: observation.aliasKey) == nil {
			context.insert(makeAlias(observation))
		}
		try context.save() // coordinated-save-allow: dedicated registry container is not radio-switched
		let ids = uniqueProfiles.keys.sorted { $0.uuidString < $1.uuidString }
		return .quarantined(ids)
	}
}
