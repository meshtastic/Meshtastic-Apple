//
//  ConnectView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Bonjour-discovered nodes (tap to connect) plus manual host / port entry,
//  under a Meshtastic logo hero.
//

import SwiftUI

struct ConnectView: View {
	@Bindable var client: MeshClient
	@StateObject private var discovery = NodeDiscovery()

	@AppStorage("tv.lastHost") private var host: String = ""
	@AppStorage("tv.lastPort") private var portText: String = "4403"

	var body: some View {
		NavigationStack {
			HStack(alignment: .top, spacing: 60) {
				hero
					.frame(maxWidth: 640)

				Form {
					discoveredSection

					Section("Manual Connection") {
						TextField("IP address or hostname", text: $host)
							.keyboardType(.URL)
							.textContentType(.URL)
							.autocorrectionDisabled()
						TextField("Port", text: $portText)
							.keyboardType(.numberPad)
						Button {
							client.connect(host: trimmedHost, port: port)
						} label: {
							Label("Connect", systemImage: "network")
						}
						.disabled(trimmedHost.isEmpty)
					}

					if case .failed(let message) = client.state {
						Section {
							Label(message, systemImage: "exclamationmark.triangle.fill")
								.foregroundStyle(.red)
						}
					}
				}
			}
			.padding(.top, 40)
		}
	}

	private var hero: some View {
		VStack(alignment: .leading, spacing: 28) {
			Image("m-logo-white")
				.resizable()
				.scaledToFit()
				.frame(width: 340)
			Text("Meshtastic")
				.font(.system(size: 64, weight: .heavy, design: .rounded))
			Text("Connect to a Meshtastic node on your network and watch the mesh live on the big screen.")
				.font(.title3)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			Label("Radios advertising TCP appear automatically", systemImage: "bonjour")
				.font(.callout)
				.foregroundStyle(Color("LightIndigo"))
		}
		.frame(maxHeight: .infinity, alignment: .top)
	}

	@ViewBuilder
	private var discoveredSection: some View {
		Section {
			if discovery.discovered.isEmpty {
				HStack(spacing: 16) {
					ProgressView()
					Text("Searching the local network…")
						.foregroundStyle(.secondary)
				}
			} else {
				ForEach(discovery.discovered) { node in
					Button {
						client.connect(host: node.host, port: node.port)
					} label: {
						HStack(spacing: 16) {
							Image(systemName: "antenna.radiowaves.left.and.right")
								.foregroundStyle(Color("LightIndigo"))
							VStack(alignment: .leading, spacing: 4) {
								Text(node.name)
								Text(verbatim: "\(node.host):\(String(node.port))")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
					}
				}
			}
		} header: {
			Text("Discovered Nodes")
		}
		.onAppear { discovery.start() }
		.onDisappear { discovery.stop() }
	}

	private var trimmedHost: String {
		host.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var port: Int {
		Int(portText.trimmingCharacters(in: .whitespaces)) ?? 4403
	}
}
