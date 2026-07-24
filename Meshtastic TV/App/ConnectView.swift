//
//  ConnectView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Bonjour-discovered nodes (tap to connect) plus manual host / port entry.
//

import SwiftUI

struct ConnectView: View {
	@Bindable var client: MeshClient
	@StateObject private var discovery = NodeDiscovery()

	@AppStorage("tv.lastHost") private var host: String = ""
	@AppStorage("tv.lastPort") private var portText: String = "4403"

	var body: some View {
		NavigationStack {
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
			.navigationTitle("Meshtastic")
			.onAppear { discovery.start() }
			.onDisappear { discovery.stop() }
		}
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
							VStack(alignment: .leading, spacing: 4) {
								Text(node.name)
								Text("\(node.host):\(node.port)")
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
	}

	private var trimmedHost: String {
		host.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var port: Int {
		Int(portText.trimmingCharacters(in: .whitespaces)) ?? 4403
	}
}
