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
	var addChannel: Bool = false
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
					let success = bleManager.saveChannelSet(base64UrlString: channelSetLink, addChannel: addChannel)
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
