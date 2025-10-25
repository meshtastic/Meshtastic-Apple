//
//  ChannelHelp.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/18/25.
//

import SwiftUI

struct ChannelsHelp: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		ScrollView {
			Label("Channels Help", systemImage: "questionmark.circle")
				.font(.title)
				.padding(.vertical)
			VStack(alignment: .leading) {
				HStack {
					CircleText(text: String(0), color: .accentColor)
						.brightness(0.2)
						.offset(y: -10)
					Text("A channel index of 0 indicates the primary channel where broadcast packets are sent from. Location data is broadcast from the first channel where it is enabled with firmware 2.7 forward.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
						.padding(.leading, 7)
				}
				HStack {
					Image(systemName: "lock.fill")
						.padding(.leading)
						.padding(.trailing, 7)
						.foregroundColor(Color.green)
						.font(.title)
					Text("A green lock means the channel is securely encrypted with either a 128 or 256 bit AES key.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
				}
				HStack {
					Image(systemName: "lock.open.fill")
						.padding(.leading)
						.foregroundColor(Color.yellow)
						.font(.title)
					Text("A yellow open lock means the channel is not securely encrypted but it is not used for precise location data, it uses either no key at all or a 1 byte known key.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
				}
				HStack {
					Image(systemName: "lock.open.fill")
						.padding(.leading)
						.foregroundColor(Color.red)
						.font(.title)
					Text("A red open lock means the channel is not securely encrypted and is used for precise location data, it uses either no key at all or a 1 byte known key.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
				}
				HStack {
					Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
						.padding(.leading)
						.symbolRenderingMode(.multicolor)
						.foregroundColor(Color.red)
						.font(.title)
					Text("A red open lock with a warning means the channel is not securely encrypted and is used for precise location data which is being uplinked to the internet via MQTT, it uses either no key at all or a 1 byte known key.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
				}
			}

#if targetEnvironment(macCatalyst)
		Spacer()
		Button {
			dismiss()
		} label: {
			Label("Close", systemImage: "xmark")
		}
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding(.bottom)
#endif
		}
		.frame(minHeight: 0, maxHeight: .infinity, alignment: .leading)
		.padding()
		.backport.presentationDetents([.large])
		.backport.presentationContentInteraction(.scrolls)
		.backport.presentationDragIndicator(.visible)
		.backport.presentationBackgroundInteraction(.enabled(upThrough: .large))
	}
}

struct ChannelHelpPreviews: PreviewProvider {
	static var previews: some View {
		VStack {
			ChannelsHelp()
		}
	}
}
