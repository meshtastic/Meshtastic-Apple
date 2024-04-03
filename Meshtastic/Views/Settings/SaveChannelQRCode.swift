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
	var addChannels: Bool = false
	var bleManager: BLEManager
	@State var connectedToDevice = false

	var body: some View {
		VStack {
			Text("\(addChannels ? "Add" : "Replace all") Channels?")
				.font(.title)
			Text("These settings will \(addChannels ? "add" : "replace all") channels. The current LoRa Config will be replaced. After everything saves your device will reboot.")
				.foregroundColor(.gray)
				.font(.title3)
				.padding()

			HStack {

				Button {
					let success = bleManager.saveChannelSet(base64UrlString: channelSetLink, addChannels: addChannels)
					if success {
						dismiss()
					}

				} label: {
					Label("save", systemImage: "square.and.arrow.down")
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
					Label("cancel", systemImage: "xmark")

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
