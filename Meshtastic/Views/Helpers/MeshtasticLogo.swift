//
//  MeshtasticLogo.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/6/22.
//
import SwiftUI

struct MeshtasticLogo: View {

	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.eventFirmwarePresentation) private var eventPresentation
	@Environment(\.openEventFirmwareInfo) private var openEventFirmwareInfo

	var body: some View {
		Group {
			if let eventPresentation {
				Button {
					openEventFirmwareInfo()
				} label: {
					EventFirmwareIcon(
						edition: eventPresentation.edition,
						iconURL: eventPresentation.info.iconURL,
						size: 34
					)
				}
				.buttonStyle(.plain)
				.accessibilityLabel(
					String(
						localized: "\(eventPresentation.info.displayName ?? eventPresentation.edition.name) event information",
						comment: "VoiceOver label for the connected event firmware navigation logo"
					)
				)
			} else {
				Link(destination: URL(string: "meshtastic:///settings/about")!) {
					standardLogo
				}
			}
		}
	}

	@ViewBuilder
	private var standardLogo: some View {
		#if targetEnvironment(macCatalyst)
			VStack {
				if #available(iOS 26.0, macOS 26.0, *) {
					Image(colorScheme == .dark ? "logo-white" : "logo-black")
						.resizable()
						.foregroundColor(.accentColor)
						.scaledToFit()
				} else {
					Image("logo-white")
						.resizable()
						.foregroundColor(.accentColor)
						.scaledToFit()
				}
			}
			.padding(.bottom, 5)
			.padding(.top, 5)
		#else
		if #available(iOS 26.0, macOS 26.0, *) {
			VStack {
				Image(colorScheme == .dark ? "logo-white" : "logo-black")
					.resizable()
					.scaledToFit()
			}
		} else {
			VStack {
				Image(colorScheme == .dark ? "logo-white" : "logo-black")
					.resizable()
					.scaledToFit()
			}
			.padding(.bottom, 5)
		}
		#endif
	}
}

#Preview {
	MeshtasticLogo()
		.frame(width: 200, height: 44)
}
