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
		
		VStack {
			
			Text("Save Channel Settings?")
				.font(.title)
			
			Text("The settings embedded in this QR code will replace the current settings on your radio.")
				.foregroundColor(.gray)
				.font(.callout)
				.padding()

			Text(String(channelHash?.path ?? "URL did not pass through properly"))
				.font(.title2)
				.padding()
			
			Text("This does not work yet.")
				.font(.callout)
				.padding()
			
			
			Text("Swipe down to dismiss.")
				.padding()
		}
	}
}
