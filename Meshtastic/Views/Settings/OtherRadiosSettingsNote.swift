//
//  OtherRadiosSettingsNote.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// Says which radio Settings configures when more than one is connected (feature 021, T089).
/// With the Node picker shown, any connected radio can be picked there and is configured over
/// its own connection; otherwise settings apply to the window's radio, and showing another
/// radio (W-13; on the Mac, its own window) configures that one.
struct OtherRadiosSettingsNote: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	/// The radio this window works with (feature 021, D-19).
	@Environment(\.windowRadio) private var windowRadio
	/// The Node picker is shown, so the other radios can be picked in it.
	var canPickRadio = false

	var body: some View {
		let shown = accessoryManager.session(for: windowRadio)?.device
		let others = accessoryManager.otherConnectedRadios(than: windowRadio)
		if let shown, !others.isEmpty {
			let otherNames = ListFormatter.localizedString(byJoining: others.map { $0.shortName ?? $0.longName ?? $0.name })
			Label {
				if canPickRadio {
					Text(String.localizedStringWithFormat(
						"To configure %@, pick it under Node. It's configured over its own connection.".localized,
						otherNames
					))
				} else {
					Text(String.localizedStringWithFormat(
						"These settings configure %1$@. To configure %2$@, show it from the Connect tab or the radio menu.".localized,
						shown.longName ?? shown.name,
						otherNames
					))
				}
			} icon: {
				Image(systemName: "antenna.radiowaves.left.and.right")
			}
			.font(.footnote)
			.foregroundStyle(.secondary)
		}
	}
}
