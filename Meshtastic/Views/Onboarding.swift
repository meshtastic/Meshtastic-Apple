//
//  Onboarding.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/21/22.
//

import SwiftUI

struct Onboarding: View {

	var body: some View {
		
		VStack {
			
			Text("🗺️ Set Your Region to Mesh and Message")
				.font(.largeTitle)
				.foregroundColor(.red)
			
			Text("Your region is currently set to UNSET, please set your device to the appropriate region under Settings > LoRa, after you set your region your Meshtastic device will reboot.")
				.font(.callout)
				.padding()
			
		}
	}
}
