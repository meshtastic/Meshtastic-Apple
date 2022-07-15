//
//  SaveChannelQRCode.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI

struct SaveChannelQRCode: View {
	
	var channelHash: URL?

	var body: some View {
		
		// Show an error if there is no e/ or other validation problems
		
		VStack {
			
			Text("Save Channel Settings?")
				.font(.title)
			
			Text("The settings embedded in this QR code will replace the current settings on your radio.")
				.foregroundColor(.gray)
				.font(.callout)
				.padding()

			Text(String(channelHash?.path ?? "empty"))
				.font(.title2)
				.padding()
			
			Text("Blah blah.")
				.font(.callout)
				.padding()
			
			
			Text("This is forever")
				.padding()
		}
	}
}
