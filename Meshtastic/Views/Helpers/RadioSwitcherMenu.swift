//
//  RadioSwitcherMenu.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// Wraps the connected-radio indicator (feature 021, T082). With one radio it's the indicator,
/// unchanged. With more, it adds a "+N" badge and becomes a menu that focuses another connected
/// radio. Observes the shared manager itself, so it needs nothing from the environment.
struct RadioSwitcherMenu<Content: View>: View {
	@ObservedObject private var accessoryManager = AccessoryManager.shared
	@ViewBuilder let content: () -> Content

	var body: some View {
		let others = accessoryManager.additionalRadioDevices
		if others.isEmpty || accessoryManager.activeConnection == nil {
			content()
		} else {
			Menu {
				if let focused = accessoryManager.activeConnection?.device {
					Section("Focused Radio") {
						Label(focused.longName ?? focused.name, systemImage: "checkmark")
					}
				}
				Section("Also Connected") {
					ForEach(others, id: \.id) { device in
						Button {
							Task {
								await switchToDevice(device, accessoryManager: accessoryManager, appState: accessoryManager.appState)
							}
						} label: {
							Label(device.longName ?? device.name, systemImage: "scope")
						}
						.disabled(device.connectionState != .connected)
					}
				}
			} label: {
				HStack(spacing: 4) {
					content()
					Text("+\(others.count)")
						.font(.caption2.bold())
						.padding(.horizontal, 5)
						.padding(.vertical, 1)
						.background(Capsule().fill(Color.accentColor.opacity(0.2)))
						.accessibilityHidden(true)
				}
			}
			.accessibilityHint(String.localizedStringWithFormat("%d more radios connected. Opens a menu to focus another radio.".localized, others.count))
		}
	}
}
