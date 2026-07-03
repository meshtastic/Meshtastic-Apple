//
//  ChannelHelp.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/18/25.
//

import SwiftUI

struct ChannelsHelp: View {
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List {
				Section {
					HelpItem(
						symbol: AnyView(
							CircleText(text: String(0), color: .accentColor)
								.brightness(0.2)
						),
						title: String(localized: "Primary Channel"),
						subtitle: String(localized: "A channel index of 0 indicates the primary channel where broadcast packets are sent. On firmware 2.6.10 and later, location data is broadcast from the first channel where it is enabled.")
					)
				} header: {
					Text("Channel Index")
				}
				Section {
					HelpItem(
						symbol: AnyView(
							Image(systemName: "location.fill")
								.font(.title3)
								.foregroundColor(.green)
						),
						title: String(localized: "Location Sharing"),
						subtitle: String(localized: "Marks the channel currently used for position broadcasts.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "icloud.and.arrow.up")
								.font(.title3)
								.foregroundColor(.blue)
						),
						title: String(localized: "MQTT Uplink"),
						subtitle: String(localized: "Packets from this channel can be forwarded to MQTT when MQTT is configured.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "icloud.and.arrow.down")
								.font(.title3)
								.foregroundColor(.blue)
						),
						title: String(localized: "MQTT Downlink"),
						subtitle: String(localized: "MQTT packets for this channel can be sent back over LoRa when MQTT is configured.")
					)
				} header: {
					Text("Channel Icons")
				}
				Section {
					HelpItem(
						symbol: AnyView(
							Image(systemName: "lock.fill")
								.font(.title3)
								.foregroundColor(.green)
						),
						title: String(localized: "Securely Encrypted"),
						subtitle: String(localized: "The channel is encrypted with a 128 or 256 bit AES key.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "lock.open.fill")
								.font(.title3)
								.foregroundColor(.yellow)
						),
						title: String(localized: "Not Securely Encrypted"),
						subtitle: String(localized: "The channel uses no key or a 1 byte known key but is not used for precise location data.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "lock.open.fill")
								.font(.title3)
								.foregroundColor(.red)
						),
						title: String(localized: "Insecure with Location"),
						subtitle: String(localized: "The channel is not securely encrypted and is used for precise location data.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
								.font(.title3)
								.symbolRenderingMode(.multicolor)
								.foregroundColor(.red)
						),
						title: String(localized: "Insecure with MQTT"),
						subtitle: String(localized: "The channel is not securely encrypted and precise location data is being uplinked to the internet via MQTT.")
					)
				} header: {
					Text("Channel Security")
				}
			}
			.navigationTitle("Channels Help")
			.navigationBarTitleDisplayMode(.inline)
		}

		#if targetEnvironment(macCatalyst)
		.overlay(alignment: .topLeading) {
			Button {
				dismiss()
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.system(size: 34))
					.symbolRenderingMode(.palette)
					.foregroundStyle(.white, Color(.systemGray3))
			}
			.buttonStyle(.plain)
			.padding(.top, 12)
			.padding(.leading, 14)
		}
		#endif
		.presentationDetents([.large])
		.presentationContentInteraction(.scrolls)
		#if !targetEnvironment(macCatalyst)
		.presentationDragIndicator(.visible)
		#endif
		.presentationBackgroundInteraction(.enabled(upThrough: .large))


	}
}

struct ChannelHelpPreviews: PreviewProvider {
	static var previews: some View {
		ChannelsHelp()
	}
}
