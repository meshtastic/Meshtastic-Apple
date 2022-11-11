//
//  SaveChannelQRCode.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI

struct SaveChannelQRCode: View {
	
	@Environment(\.dismiss) private var dismiss
	
	var channelSetLink: String
	var bleManager: BLEManager
	@State var connectedToDevice = false

	var body: some View {
		VStack {
			Text("Save Channel Settings?")
				.font(.title)
			Text("These settings will replace the current LoRa Config and Channel Settings on your radio. After everything saves your device will reboot.")
				.foregroundColor(.gray)
				.font(.callout)
				.padding()
			
			HStack {
				
				Button {
					let success = bleManager.saveChannelSet(base64UrlString: channelSetLink)
					if success {
						dismiss()
					}
					
				} label: {
					Label("Save", systemImage: "square.and.arrow.down")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.disabled(!connectedToDevice)
				
			#if targetEnvironment(macCatalyst)
				Button {
					dismiss()
				} label: {
					Label("Cancel", systemImage: "xmark")
					
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
			#endif
			}
		}
		.onAppear {
			connectedToDevice = bleManager.connectToPreferredPeripheral()
		}
	}
}
