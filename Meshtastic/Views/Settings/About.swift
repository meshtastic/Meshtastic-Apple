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
		
		VStack{
			
			List {
				Section(header: Text("What is Meshtastic?")) {
					Text("An open source, off-grid, decentralized, mesh network built to run on affordable, low-power devices.")
						.font(.title3)
					
				}
				Section(header: Text("Apple Apps")) {
					Button("Review the app") {
						if let scene = UIApplication.shared.connectedScenes
							.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
							SKStoreReviewController.requestReview(in: scene)
						}
					}
					.font(.title2)
					Link("Sponsor App Development", destination: URL(string: "https://github.com/sponsors/garthvh")!)
						.font(.title2)
					Link("GitHub Repository", destination: URL(string: "https://github.com/meshtastic/Meshtastic-Apple")!)
						.font(.title2)
				}
				if locale.region?.identifier ?? "no locale" == "US" {
					Section(header: Text("Get Devices")) {
						Link("Buy Complete Radios", destination: URL(string: "https://www.etsy.com/shop/GarthVH")!)
							.font(.title2)
					}
				}
				Section(header: Text("Project information")) {
					Link("Website", destination: URL(string: "https://meshtastic.org")!)
						.font(.title2)
					Link("Documentation", destination: URL(string: "https://meshtastic.org/docs/getting-started")!)
						.font(.title2)
				}
				Text("Meshtastic Copyright(c) Meshtastic LLC")
					.font(.caption)
			}
		}
		.navigationTitle("About")
		.navigationBarTitleDisplayMode(.inline)
	}
}
