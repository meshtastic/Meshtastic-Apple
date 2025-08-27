//
//  MeshtasticLogo.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/6/22.
//
import SwiftUI

struct MeshtasticLogo: View {

	@Environment(\.colorScheme) var colorScheme

	var body: some View {
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
