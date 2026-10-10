//
//  RadioSwitcherMenu.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI
import UIKit

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
		let others = accessoryManager.otherConnectedRadios(than: windowRadio)
		if others.isEmpty || shown == nil {
			content()
		} else {
#if targetEnvironment(macCatalyst)
			// The Mac toolbar turns a toolbar item holding a SwiftUI menu into one menu button that
			// shows only the item's first image (the RX/TX arrow), so the indicator lost its link
			// icon, name and badge. A UIKit pull-down button isn't taken apart: the item stays as it is
			// with one radio, and the menu opens from the indicator.
			RadioPullDownButton(
				label: AnyView(label(others.count)),
				menu: pullDownMenu(shown: shown, others: others),
				accessibilityLabel: accessibilityLabel(shown),
				accessibilityHint: accessibilityHint(others.count)
			)
			.fixedSize()
#else
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
				label(others.count)
			}
			.accessibilityHint(accessibilityHint(others.count))
#endif
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

	private func accessibilityLabel(_ shown: Device?) -> String {
		String(localized: "Connected to Bluetooth device", comment: "VoiceOver label for a connected Bluetooth device")
			+ ", " + (shown?.shortName ?? shown?.name ?? "")
	}

	private func accessibilityHint(_ count: Int) -> String {
		String.localizedStringWithFormat("%d more radios connected. Opens a menu to show another radio.".localized, count)
	}

	/// The same menu as on iPhone and iPad, as a UIKit menu.
	private func pullDownMenu(shown: Device?, others: [Device]) -> UIMenu {
		var sections: [UIMenuElement] = []
		if let shown {
			sections.append(UIMenu(title: "This Radio".localized, options: .displayInline, children: [
				UIAction(title: shown.longName ?? shown.name, attributes: .disabled, state: .on) { _ in }
			]))
		}
		let select = selectWindowRadio
		sections.append(UIMenu(title: "Also Connected".localized, options: .displayInline, children: others.map { device in
			UIAction(
				title: device.longName ?? device.name,
				image: UIImage(systemName: "scope"),
				attributes: device.connectionState == .connected ? [] : .disabled
			) { _ in
				select(device.id)
			}
		}))
		return UIMenu(children: sections)
	}
}

#if targetEnvironment(macCatalyst)
/// A pull-down button showing `label`, a SwiftUI view, with `menu` opening on a click (feature
/// 021). See `RadioSwitcherMenu` for why the Mac needs it.
private struct RadioPullDownButton: UIViewRepresentable {
	let label: AnyView
	let menu: UIMenu
	let accessibilityLabel: String
	let accessibilityHint: String

	@MainActor
	final class Coordinator {
		let host = UIHostingController(rootView: AnyView(EmptyView()))
	}

	func makeCoordinator() -> Coordinator { Coordinator() }

	func makeUIView(context: Context) -> UIButton {
		let button = UIButton(type: .custom)
		button.showsMenuAsPrimaryAction = true
		let hosted: UIView = context.coordinator.host.view
		hosted.backgroundColor = .clear
		hosted.isUserInteractionEnabled = false
		hosted.accessibilityElementsHidden = true
		hosted.translatesAutoresizingMaskIntoConstraints = false
		button.addSubview(hosted)
		NSLayoutConstraint.activate([
			hosted.leadingAnchor.constraint(equalTo: button.leadingAnchor),
			hosted.trailingAnchor.constraint(equalTo: button.trailingAnchor),
			hosted.topAnchor.constraint(equalTo: button.topAnchor),
			hosted.bottomAnchor.constraint(equalTo: button.bottomAnchor)
		])
		return button
	}

	func updateUIView(_ button: UIButton, context: Context) {
		context.coordinator.host.rootView = label
		button.menu = menu
		button.accessibilityLabel = accessibilityLabel
		button.accessibilityHint = accessibilityHint
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
		context.coordinator.host.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
	}
}
#endif
