//
//  About.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/6/22.
//
import SwiftUI
import StoreKit
import SwiftDraw

struct AboutMeshtastic: View {

	var body: some View {

		VStack {
			List {
				Section(header: Text("What is Meshtastic?")) {
					Text("An open source, off-grid, decentralized, mesh network that runs on affordable, low-power radios.")
						.font(.title3)

				}
				Section(header: Text("Apple Apps")) {

					HStack {
						RotatingHardwareImage()
							.frame(width: 75, height: 75)
							.padding()
						VStack(alignment: .leading) {
							Link("Need Hardware?", destination: URL(string: "https://meshtastic.org/#hardware")!)
								.font(.title2)
							Text("Meshtastic requires a compatible device. Our backers and partners offer ready-to-use hardware. Here are some of the most popular options.")
								.font(.callout)
						}
					}
					Link("Sponsor App Development", destination: URL(string: "https://github.com/sponsors/garthvh")!)
						.font(.title2)
					Link("GitHub Repository", destination: URL(string: "https://github.com/meshtastic/Meshtastic-Apple")!)
						.font(.title2)
					Button("Review the app") {
						if let scene = UIApplication.shared.connectedScenes
							.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
							AppStore.requestReview(in: scene)
						}
					}
					.font(.title2)

					Text("Version: \(Bundle.main.appVersionLong) (\(Bundle.main.appBuild))")
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
		.navigationTitle("About")
		.navigationBarTitleDisplayMode(.inline)
	}
}

/// Cycles through the devices featured in the Need Hardware? section on
/// meshtastic.org, using the device SVGs already bundled in the app.
private struct RotatingHardwareImage: View {

	private static let imageNames = [
		"t-deck.svg",
		"muzi_r1_neo.svg",
		"tracker-t1000-e.svg",
		"station-g2.svg",
		"rak_wismesh_tag.svg",
		"heltec_mesh_pocket.svg",
		"thinknode_m1.svg"
	]

	@State private var svgs: [SVG] = []
	@State private var index = 0

	private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

	var body: some View {
		ZStack {
			if !svgs.isEmpty {
				SVGView(svg: svgs[index % svgs.count])
					.resizable()
					.aspectRatio(contentMode: .fit)
					.id(index)
					.transition(.opacity)
			}
		}
		.task {
			// The device SVGs are copied flat into the bundle root, not into
			// an images/ subdirectory.
			svgs = Self.imageNames.compactMap { name in
				guard let url = Bundle.main.url(forResource: name, withExtension: nil),
					  let data = try? Data(contentsOf: url) else { return nil }
				return SVG(data: data)
			}
		}
		.onReceive(timer) { _ in
			guard svgs.count > 1 else { return }
			withAnimation(.easeInOut(duration: 0.5)) {
				index += 1
			}
		}
	}
}

#Preview {
	NavigationView {
		AboutMeshtastic()
	}
}
