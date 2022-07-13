//
//  InvalidVersion.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI

struct InvalidVersion: View {
	
	@State var errorText = ""

	var body: some View {
		
		VStack {
			
			Text("🚨 Unsupported Firmware Version")
				.font(.largeTitle)
				.foregroundColor(.red)
			
			Text(errorText)
				.font(.title2)
				.padding()
			
			Text("Version 1.3 includes breaking changes to devices and the client apps. The version 1.3 app does not support 1.2 nodes, there are two builds for 1.2 under Versions & Build Groups in TestFlight that will be available until early September 2022.")
				.font(.callout)
				.padding()
			
			
			Link("Upgrade your Firmware", destination: URL(string: "https://meshtastic.org/docs/getting-started/flashing-firmware/")!)
			
			Text("Only manual firmware upgrade methods are working for version 1.3.")
				.padding()
		}
	}
}
