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
	private enum ErrorFocus: Hashable {
		case connection
		case discovery
	}

	@Bindable var client: MeshClient
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var discovery = NodeDiscovery()
	@AccessibilityFocusState private var errorFocus: ErrorFocus?

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
								.foregroundStyle(Color("MeshtasticError"))
								.accessibilityLabel("Connection error: \(message)")
								.accessibilityFocused($errorFocus, equals: .connection)
								.onAppear { errorFocus = .connection }
						}
					}

					Section {
						NavigationLink {
							SettingsView()
						} label: {
							Label("Settings", systemImage: "gearshape")
						}
					}
				}
				// Inset focused controls without hiding native Form section headers.
				.safeAreaPadding(.horizontal, TVTheme.connectHorizontalInset)
			}
			.padding(.top, TVTheme.screenPadding)
		}
		.onChange(of: scenePhase) { _, phase in
			discovery.handle(scenePhase: phase)
		}
	}

	private var hero: some View {
		VStack(alignment: .leading, spacing: 28) {
			Image(decorative: "meshtastic-wordmark-white")
				.resizable()
				.scaledToFit()
				.frame(width: 620)
			Text("Connect to a Meshtastic node on your network and watch the mesh live on the big screen.")
				.font(.title3)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			Label("Radios advertising TCP appear automatically", systemImage: "bonjour")
				.font(.callout)
				.foregroundStyle(.secondary)
		}
		.frame(maxHeight: .infinity, alignment: .top)
	}

	@ViewBuilder
	private var discoveredSection: some View {
		Section {
			if let errorMessage = discovery.errorMessage {
				Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
					.foregroundStyle(Color("MeshtasticError"))
					.accessibilityLabel("Discovery error: \(errorMessage)")
					.accessibilityFocused($errorFocus, equals: .discovery)
					.onAppear { errorFocus = .discovery }
				Button("Try Again") { discovery.retry() }
			} else if discovery.discovered.isEmpty {
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
								Text(verbatim: "\(node.host):\(String(node.port))")
									.font(.caption)
							}
						}
					}
					.tint(.primary)
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
