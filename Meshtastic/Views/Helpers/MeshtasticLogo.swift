//
//  MeshtasticLogo.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/6/22.
//
import SwiftUI

struct MeshtasticLogo: View {

	@Environment(\.colorScheme) private var colorScheme

	// The Meshtastic mark is the app's brand and is never swapped for event/edition artwork —
	// not on Connect, not anywhere. Event branding lives in the Connect screen's device box
	// (see Connect.swift), never in this top-left nav logo.
	var body: some View {
		Link(destination: URL(string: "meshtastic:///settings/about")!) {
			standardLogo
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
