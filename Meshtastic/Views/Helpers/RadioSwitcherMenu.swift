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
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.displayScale) private var displayScale
	@ViewBuilder let content: () -> Content

	var body: some View {
		let shown = accessoryManager.session(for: windowRadio)?.device
		let others = accessoryManager.otherConnectedRadios(than: windowRadio)
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
#if targetEnvironment(macCatalyst)
				drawnLabel(others.count)
#else
				label(others.count)
#endif
			}
			.accessibilityLabel(String(localized: "Connected to Bluetooth device", comment: "VoiceOver label for a connected Bluetooth device") + ", " + (shown?.shortName ?? shown?.name ?? ""))
			.accessibilityHint(String.localizedStringWithFormat("%d more radios connected. Opens a menu to show another radio.".localized, others.count))
		}
	}

	/// The indicator with a "+N" badge for the other connected radios.
	private func label(_ count: Int) -> some View {
		HStack(spacing: 4) {
			content()
			Text("+\(count)")
				.font(.caption2.bold())
				.padding(.horizontal, 5)
				.padding(.vertical, 1)
				.background(Capsule().fill(Color.accentColor.opacity(0.2)))
				.accessibilityHidden(true)
		}
	}

	/// On the Mac the toolbar shows a menu as an icon only, the first image in its label, so the
	/// indicator lost its link icon and name (the MQTT icon showed instead). Drawn as one image, in
	/// its own colours, it shows as it is, and the menu opens from it. Redrawn with the view.
	@ViewBuilder
	private func drawnLabel(_ count: Int) -> some View {
		let renderer = ImageRenderer(content: label(count).environment(\.colorScheme, colorScheme))
		let _ = renderer.scale = displayScale
		if let image = renderer.uiImage {
			Image(uiImage: image.withRenderingMode(.alwaysOriginal))
		} else {
			label(count)
		}
	}
}
