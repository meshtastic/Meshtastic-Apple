//
//  InvalidVersion.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI

struct InvalidVersion: View {

	@Environment(\.dismiss) private var dismiss

	@State var minimumVersion = ""
	@State var version = ""

	var body: some View {

		VStack {

			Text("update.firmware")
				.font(.largeTitle)
				.foregroundColor(.orange)

			Divider()
			VStack {
				Text("The Meshtastic Apple apps support firmware version \(minimumVersion) and above.")
						.font(.title2)
						.padding(.bottom)
				Link("Firmware update docs", destination: URL(string: "https://meshtastic.org/docs/getting-started/flashing-firmware/")!)
					.font(.title)
					.padding()
				Link("Additional help", destination: URL(string: "https://meshtastic.org/docs/faq")!)
					.font(.title)
					.padding()
			}
			.padding()
			Divider()
				.padding(.top)
			VStack {
				Text("🦕 End of life Version 🦖 ☄️")
					.font(.title3)
					.foregroundColor(.orange)
					.padding(.bottom)
				Text("Version \(minimumVersion) includes substantial network optimizations and extensive changes to devices and client apps. Only nodes version \(minimumVersion) and above are supported.")
					.font(.callout)
					.padding([.leading, .trailing, .bottom])

				#if targetEnvironment(macCatalyst)
					Button {
						dismiss()
					} label: {
						Label("Close", systemImage: "xmark")

					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding()
				#endif

			}.padding()
		}
	}
}
