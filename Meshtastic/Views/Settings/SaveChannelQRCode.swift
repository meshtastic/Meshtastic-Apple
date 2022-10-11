//
//  SaveChannelQRCode.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI

struct SaveChannelQRCode: View {
	var channelHash: String
	var validUrl: Bool
	
	var body: some View {
		VStack {
			if validUrl {
				Text("Save Channel Settings?")
					.font(.title)
				Text("These settings will replace the current settings on your radio.")
					.foregroundColor(.gray)
					.font(.callout)
					.padding()
				
				Text(channelHash)
					.font(.caption2)
					.padding()
				
			} else {
				Text("Invalid Channel Settings Url")
					.font(.title)
				
				Text("Error Message")
					.font(.callout)
					.foregroundColor(.red)
					.padding()
			}
		}
		.onChange(of: channelHash) { newSettings in
			
			var decodedString = newSettings.base64urlToBase64()
			
			if let decodedData = Data(base64Encoded: decodedString) {
				decodedString = String(data: decodedData, encoding: .utf8)!
				do {
					var channelSet: ChannelSet = try ChannelSet(serializedData: decodedData)
					print(channelSet)
				} catch {
					print("Invalid Meshtastic QR Code Link")
				}
			}
		}
	}
}
