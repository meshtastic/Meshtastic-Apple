//
//  OtherRadiosSettingsNote.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// Says which radio Settings configures when more than one is connected (feature 021, T089):
/// settings always apply to the focused radio, and focusing another radio configures that one.
struct OtherRadiosSettingsNote: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	var body: some View {
		let others = accessoryManager.additionalRadioDevices
		if !others.isEmpty, let focused = accessoryManager.activeConnection?.device {
			let otherNames = ListFormatter.localizedString(byJoining: others.map { $0.shortName ?? $0.longName ?? $0.name })
			Label {
				Text(String.localizedStringWithFormat(
					"These settings configure %1$@. To configure %2$@, focus it from the Connect tab or the radio menu.".localized,
					focused.longName ?? focused.name,
					otherNames
				))
			} icon: {
				Image(systemName: "antenna.radiowaves.left.and.right")
			}
			.font(.footnote)
			.foregroundStyle(.secondary)
		}
	}
}
