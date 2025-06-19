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
					Text("A channel index of 0 indicates the primary channel where all broadcast packets are sent from.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
				}
				HStack {
					Image(systemName: "lock.fill")
						.padding(.bottom)
						.foregroundColor(Color.green)
						.font(.largeTitle)
					Text("A green lock means the channel is securely encrypted with either a 128 or 256 bit AES key.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
				}
				HStack {
					Image(systemName: "lock.slash.fill")
						.padding(.bottom)
						.foregroundColor(Color.red)
						.font(.largeTitle)
					Text("A red lock with a slash means the channel is not securely encrypted, it uses either no key at all or a 1 byte known key. Traffic on this channel is easily intercepted.")
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
		.presentationDetents([.large])
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .large))
	}
}

struct ChannelHelpPreviews: PreviewProvider {
	static var previews: some View {
		VStack {
			ChannelsHelp()
		}
	}
}
