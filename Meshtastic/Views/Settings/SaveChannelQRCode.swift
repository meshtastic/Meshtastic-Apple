//
//  SaveChannelQRCode.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI

struct SaveChannelQRCode: View {
	
	@Environment(\.presentationMode) private var presentationMode
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
			

				Button {
					let success = bleManager.saveChannelSet(base64UrlString: channelSetLink)
					if success {
						presentationMode.wrappedValue.dismiss()
					}
					
				} label: {
					Label("Save", systemImage: "square.and.arrow.down")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.disabled(!connectedToDevice)
		
		}
		.onAppear {
			connectedToDevice = bleManager.connectToPreferredPeripheral()
		}
	}
}
