//
//  RemoveRadioConfirmation.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

// MARK: - Remove Radio (feature 021, D-18, W-02)

/// One of the user's radios to remove, for the confirmation.
struct RadioToRemove: Identifiable, Equatable {
	let nodeNum: Int64
	let name: String

	var id: Int64 { nodeNum }
}

/// Asks before Remove Radio, the same wherever it's offered: beside Disconnect, on a radio that's
/// off, and in Settings. The radio itself isn't changed; the app forgets it and the data only it
/// has, and its window closes.
///
/// The views inside ask through `askToRemoveRadio`, so the dialog belongs to the view this is
/// attached to (a list) and stays up when the row that asked goes away, as a radio's row does
/// when it connects, disconnects or moves between sections.
struct RemoveRadioConfirmation: ViewModifier {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Binding var radio: RadioToRemove?
	/// Runs the removal; `AccessoryManager.removeRadio(_:)` when nil.
	let remove: ((RadioToRemove) -> Void)?

	func body(content: Content) -> some View {
		content
			.environment(\.askToRemoveRadio, AskToRemoveRadioAction { radio = $0 })
			.confirmationDialog(
				"Remove \(radio?.name ?? "")?",
				isPresented: Binding(get: { radio != nil }, set: { if !$0 { radio = nil } }),
				titleVisibility: .visible,
				presenting: radio
			) { radio in
				Button("Remove Radio", role: .destructive) {
					if let remove {
						remove(radio)
					} else {
						Task { await accessoryManager.removeRadio(radio.nodeNum) }
					}
				}
			} message: { radio in
				if accessoryManager.hasSeveralRadios {
					Text("Removes \(radio.name) and the messages and nodes only it has from this device. Anything your other radios also have is kept. The radio itself isn't changed, and you can add it again later.")
				} else {
					Text("Removes \(radio.name) and its messages and nodes from this device. Favorites are kept. The radio itself isn't changed, and you can add it again later.")
				}
			}
	}
}

extension View {
	/// Asks before removing `radio` when it's set (D-18).
	func removeRadioConfirmation(_ radio: Binding<RadioToRemove?>, remove: ((RadioToRemove) -> Void)? = nil) -> some View {
		modifier(RemoveRadioConfirmation(radio: radio, remove: remove))
	}
}

/// Asks to remove a radio, through the nearest `removeRadioConfirmation` above (D-18).
struct AskToRemoveRadioAction {
	let ask: @MainActor (RadioToRemove) -> Void

	@MainActor
	func callAsFunction(_ radio: RadioToRemove) {
		ask(radio)
	}
}

private struct AskToRemoveRadioKey: EnvironmentKey {
	static let defaultValue: AskToRemoveRadioAction? = nil
}

extension EnvironmentValues {
	/// Asks to remove a radio; nil where no confirmation is set up, and Remove isn't offered.
	var askToRemoveRadio: AskToRemoveRadioAction? {
		get { self[AskToRemoveRadioKey.self] }
		set { self[AskToRemoveRadioKey.self] = newValue }
	}
}
