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
		VStack {
			Image(colorScheme == .dark ? "logo-white" : "logo-black")
				.resizable()
				.scaledToFit()
		}
		.padding(.bottom, 5)
		.offset(x: -15)
	}
}
