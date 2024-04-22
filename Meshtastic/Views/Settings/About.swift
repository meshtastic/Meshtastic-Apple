//
//  About.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/6/22.
//
import SwiftUI
import StoreKit

struct AboutMeshtastic: View {

	let locale = Locale.current

	var body: some View {

		VStack {

			List {
				Section(header: Text("What is Meshtastic?")) {
					Text("An open source, off-grid, decentralized, mesh network that runs on affordable, low-power radios.")
						.font(.title3)

				}
				Section(header: Text("Apple Apps")) {
					
					if locale.region?.identifier ?? "US" == "US" {
						HStack {
							Image("SOLAR_NODE")
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(width: 75)
								.cornerRadius(5)
								.padding()
							VStack(alignment: .leading) {
								Link("Buy Complete Radios", destination: URL(string: "http://garthvh.com")!)
									.font(.title2)
								Text("Get custom waterproof solar and detection sensor router nodes, aluminium desktop nodes and rugged handsets.")
									.font(.callout)
							}
						}
					}
					Link("Help with App Development", destination: URL(string: "https://github.com/meshtastic/Meshtastic-Apple")!)
						.font(.title2)
					Button("Review the app") {
						if let scene = UIApplication.shared.connectedScenes
							.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
							SKStoreReviewController.requestReview(in: scene)
						}
					}
					.font(.title2)
					
					Text("Version: \(Bundle.main.appVersionLong) (\(Bundle.main.appBuild)) ")
				}

				Section(header: Text("Project information")) {
					Link("Website", destination: URL(string: "https://meshtastic.org")!)
						.font(.title2)
					Link("Documentation", destination: URL(string: "https://meshtastic.org/docs/getting-started")!)
						.font(.title2)
				}
				Text("Meshtastic® Copyright Meshtastic LLC")
					.font(.caption)
			}
		}
		.navigationTitle("about")
		.navigationBarTitleDisplayMode(.inline)
	}
}
