//
//  SecurityVersionNag.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2024.
//
import SwiftUI

struct SecurityVersionNag: View {

	@Environment(\.dismiss) private var dismiss

	let minimumSecureVersion: String
	let version: String

	var body: some View {
		VStack(spacing: 0) {
			ScrollView {
				VStack(spacing: 20) {
					Image(systemName: "shield.slash.fill")
						.font(.system(size: 60))
						.foregroundColor(.red)
						.padding(.top, 40)

					Text("Security Update Recommended")
						.font(.largeTitle.bold())
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)

					VStack(spacing: 8) {
						if !version.isEmpty {
							Label {
								Text("Connected firmware: **\(version)**")
							} icon: {
								Image(systemName: "wifi.exclamationmark")
									.foregroundColor(.orange)
							}
							.font(.body)
						}
						Label {
							Text("Recommended secure version: **\(minimumSecureVersion)**")
						} icon: {
							Image(systemName: "checkmark.shield.fill")
								.foregroundColor(.green)
						}
						.font(.body)
					}
					.padding()
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)

					VStack(alignment: .leading, spacing: 12) {
						Text("Security Advisory")
							.font(.headline)
						Text("Your connected device is running firmware older than **\(minimumSecureVersion)**, which contains known security vulnerabilities. Updating your firmware is strongly recommended to protect your device and mesh network.")
							.font(.body)
							.foregroundColor(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
					.padding()
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)
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
					}
					.padding()
					.background(Color(.secondarySystemBackground))
					.cornerRadius(12)
					.padding(.horizontal)
				}
				.padding(.bottom, 20)
			}

			Button {
				dismiss()
			} label: {
				Text("Dismiss")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
		}
	}
}
