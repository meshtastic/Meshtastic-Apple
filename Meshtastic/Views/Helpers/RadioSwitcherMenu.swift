//
//  RadioSwitcherMenu.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// Wraps the connected-radio indicator (feature 021, T082). With one radio it's the indicator,
/// unchanged. With more, it adds a "+N" badge and becomes a menu that shows another connected
/// radio in this window (W-13).
struct RadioSwitcherMenu<Content: View>: View {
	@ObservedObject private var accessoryManager = AccessoryManager.shared
	@Environment(\.windowRadio) private var windowRadio
	@Environment(\.selectWindowRadio) private var selectWindowRadio
	@ViewBuilder let content: () -> Content

	var body: some View {
		let shown = accessoryManager.session(for: windowRadio)?.device
		let others = accessoryManager.connectedRadios.filter { $0.id != shown?.id }
		if others.isEmpty || shown == nil {
			content()
		} else {
			Menu {
				if let shown {
					Section("This Radio") {
						Label(shown.longName ?? shown.name, systemImage: "checkmark")
					}
				}
				Section("Also Connected") {
					ForEach(others, id: \.id) { device in
						Button {
							selectWindowRadio(device.id)
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
			.accessibilityHint(String.localizedStringWithFormat("%d more radios connected. Opens a menu to show another radio.".localized, others.count))
		}
	}
}
