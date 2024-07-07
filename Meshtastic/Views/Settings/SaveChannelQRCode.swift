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
	@State var showError: Bool = false
	@State var connectedToDevice = false

	var body: some View {
		VStack {
			Text("\(addChannels ? "Add" : "Replace all") Channels?")
				.font(.title)
			Text("These settings will \(addChannels ? "add" : "replace all") channels. The current LoRa Config will be replaced, if there are substantial changes to the LoRa config the device will reboot")
				.fixedSize(horizontal: false, vertical: true)
				.foregroundColor(.gray)
				.font(.title3)
				.padding()

			if showError {
				Text("Channels being added from the QR code did not save. When adding channels the names must be unique.")
					.fixedSize(horizontal: false, vertical: true)
					.foregroundColor(.red)
					.font(.callout)
					.padding()
			}
			HStack {
				if !showError {
					Button {
						let success = bleManager.saveChannelSet(base64UrlString: channelSetLink, addChannels: addChannels)
						if success {
							dismiss()
						} else {
							showError = true
						}
					} label: {
						Label("save", systemImage: "square.and.arrow.down")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding()
					.disabled(!connectedToDevice)
				} else {
					Button {
						dismiss()
					} label: {
						Label("cancel", systemImage: "xmark")

					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding()
				}

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
