//
//  MeshChannelSelection.swift
//  Meshtastic
//

import Foundation
import MeshtasticProtobufs

struct MeshChannelSelection: Sendable {
	let snapshot: MeshShareSnapshot

	enum SelectionError: LocalizedError, Equatable {
		case noChannels
		case invalidChannel
		case invalidLoRaConfig

		var errorDescription: String? {
			switch self {
			case .noChannels:
				return "Select at least one channel."
			case .invalidChannel:
				return "A saved channel could not be decoded."
			case .invalidLoRaConfig:
				return "Saved radio settings could not be decoded."
			}
		}
	}

	var defaultSelectedIndexes: Set<Int32> {
		Set(snapshot.channels.map(\.index))
	}

	func url(selectedIndexes: Set<Int32>, mode: MeshChannelImportMode) throws -> String {
		guard !selectedIndexes.isEmpty else {
			throw SelectionError.noChannels
		}

		var channelSet = ChannelSet()
		do {
			channelSet.settings = try snapshot.channels
				.filter { selectedIndexes.contains($0.index) }
				.sorted { $0.index < $1.index }
				.map { try ChannelSettings(serializedBytes: $0.settingsData) }
		} catch {
			throw SelectionError.invalidChannel
		}

		guard !channelSet.settings.isEmpty else {
			throw SelectionError.noChannels
		}

		if mode == .replace {
			do {
				channelSet.loraConfig = try Config.LoRaConfig(serializedBytes: snapshot.loraConfigData)
			} catch {
				throw SelectionError.invalidLoRaConfig
			}
		}
		return try MeshtasticChannelURL.urlString(for: channelSet, addChannels: mode == .add)
	}
}
