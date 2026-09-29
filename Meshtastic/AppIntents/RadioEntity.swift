//
//  RadioEntity.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import AppIntents
import Foundation

/// One of the user's radios, by name, for Siri and Shortcuts (feature 021, W-10, T320): "Send a
/// message via Base Station". Its id is the radio's node number.
struct RadioEntity: AppEntity {
	static let typeDisplayRepresentation: TypeDisplayRepresentation = "Radio"
	static let defaultQuery = RadioEntityQuery()

	let id: Int
	let name: String

	var nodeNum: Int64 { Int64(id) }

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(name)")
	}
}

/// The user's radios in the store, the connected ones first.
struct RadioEntityQuery: EntityStringQuery {
	func entities(for identifiers: [Int]) async throws -> [RadioEntity] {
		await radios().filter { identifiers.contains($0.id) }
	}

	func entities(matching string: String) async throws -> [RadioEntity] {
		await radios().filter { $0.name.localizedCaseInsensitiveContains(string) }
	}

	func suggestedEntities() async throws -> [RadioEntity] {
		await radios()
	}

	private func radios() async -> [RadioEntity] {
		let stored = await MeshPackets.shared.storedRadios()
		let connected = await MainActor.run { Set(AccessoryManager.shared.connectedRadioNums) }
		return stored
			.sorted { connected.contains($0.nodeNum) && !connected.contains($1.nodeNum) }
			.map { RadioEntity(id: Int($0.nodeNum), name: $0.name) }
	}
}

/// Makes a radio the one Siri, CarPlay and Shortcuts use when a command doesn't name one
/// (W-11): "Set my Meshtastic radio".
struct SetMeshtasticRadioIntent: AppIntent {
	static let title: LocalizedStringResource = "Set the Radio for Siri and CarPlay"
	static let description = IntentDescription("The radio Siri, CarPlay and Shortcuts use when a command doesn't name one.")

	@Parameter(title: "Radio")
	var radio: RadioEntity

	static var parameterSummary: some ParameterSummary {
		Summary("Use \(\.$radio) for Siri and CarPlay")
	}

	func perform() async throws -> some IntentResult & ProvidesDialog {
		UserDefaults.setServiceRadio(radio.nodeNum, for: .carPlay)
		await AccessoryManager.shared.refreshShareSnapshot()
		return .result(dialog: "\(radio.name) is now the radio for Siri and CarPlay.")
	}
}
