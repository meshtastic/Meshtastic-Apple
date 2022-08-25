//
//  SaveChannelQRCode.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI

struct SaveChannelQRCode: View {
	
	var channelHash: String

	var body: some View {
		
		VStack {
			
			Text("Save Channel Settings?")
				.font(.title)
			
			Text("The settings embedded in this QR code will replace the current settings on your radio.")
				.foregroundColor(.gray)
				.font(.callout)
				.padding()

			Text(channelHash)
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
