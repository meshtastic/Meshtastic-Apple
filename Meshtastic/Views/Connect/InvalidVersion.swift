//
//  InvalidVersion.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/13/22.
//
import SwiftUI

struct InvalidVersion: View {

	@Environment(\.dismiss) private var dismiss

	let minimumVersion: String
	let version: String

	var body: some View {
		VStack(spacing: 0) {
			ScrollView {
				VStack(spacing: 20) {
					Image(systemName: "exclamationmark.triangle.fill")
						.font(.system(size: 60))
						.foregroundColor(.orange)
						.padding(.top, 40)

					Text("Firmware Update Required")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)

					VStack(spacing: 8) {
						if !version.isEmpty {
							Label {
								Text("Connected firmware: **\(version)**")
							} icon: {
								Image(systemName: "wifi.slash")
									.foregroundColor(.red)
							}
							.font(.body)
						}
						Label {
							Text("Minimum required: **\(minimumVersion)**")
						} icon: {
							Image(systemName: "checkmark.shield.fill")
								.foregroundColor(.green)
						}
						.font(.body)
					}
					.padding()
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)

					Text("The Meshtastic Apple app requires firmware version \(minimumVersion) or later. Older firmware versions are no longer supported and may have compatibility issues or missing features.")
						.font(.body)
						.foregroundColor(.secondary)
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
						.padding(.horizontal)

					VStack(alignment: .leading, spacing: 12) {
						Text("How to Update")
							.font(.headline)
						Link(destination: URL(string: "https://flasher.meshtastic.org")!) {
							Label("Open Web Flasher", systemImage: "bolt.fill")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.borderedProminent)
						.controlSize(.regular)
						.buttonBorderShape(.capsule)
						Link(destination: URL(string: "https://meshtastic.org/docs/getting-started/flashing-firmware/")!) {
							Label("Firmware Update Docs", systemImage: "book.fill")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.bordered)
						.controlSize(.regular)
						.buttonBorderShape(.capsule)
						Link(destination: URL(string: "https://meshtastic.org/docs/faq")!) {
							Label("Additional Help", systemImage: "questionmark.circle.fill")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.bordered)
						.controlSize(.regular)
						.buttonBorderShape(.capsule)
					}
					.padding()
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)
					.padding(.horizontal)
				}
				.padding(.bottom, 20)
			}

			#if targetEnvironment(macCatalyst)
			Button {
				dismiss()
			} label: {
				Label("Close", systemImage: "xmark")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			#endif
		}
	}
}
