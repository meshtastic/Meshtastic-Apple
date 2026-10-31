//
//  DeviceScreenView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import MeshtasticProtobufs
import SwiftUI

/// The connected radio's own screen, live. Streams only while this view is on screen and the
/// app is active, and stops when it closes (design#142).
struct DeviceScreenView: View {

	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.scenePhase) private var scenePhase
	let metadata: DeviceMetadataEntity

	private var aspectRatio: CGFloat {
		CGFloat(max(metadata.displayWidth, 1)) / CGFloat(max(metadata.displayHeight, 1))
	}

	private var isEInk: Bool {
		DisplayInfo.PanelClass(rawValue: Int(metadata.displayPanelClass)) == .eink
	}

	var body: some View {
		Group {
			if accessoryManager.isConnected {
				ScrollView {
					VStack(spacing: 16) {
						screen
						details
					}
					.padding(16)
					.frame(maxWidth: 640)
					.frame(maxWidth: .infinity)
				}
			} else {
				ContentUnavailableView(
					"Not Connected",
					systemImage: "display",
					description: Text("Connect to the radio to see its screen.")
				)
			}
		}
		.navigationTitle("Device Screen")
		.navigationBarTitleDisplayMode(.inline)
		.task { await startIfVisible() }
		.onDisappear {
			Task { await accessoryManager.stopDisplayMirror() }
		}
		.onChange(of: scenePhase) { _, phase in
			Task {
				if phase == .active {
					await startIfVisible()
				} else {
					await accessoryManager.stopDisplayMirror()
				}
			}
		}
		.onChange(of: accessoryManager.isConnected) { _, connected in
			// The radio forgets the stream on reconnect, so ask again.
			if connected {
				Task { await startIfVisible() }
			}
		}
		.trackScreen(.deviceScreen)
	}

	private var screen: some View {
		ZStack {
			if let image = accessoryManager.displayMirror.image {
				Image(decorative: image, scale: 1)
					.resizable()
					.interpolation(.none)
					.aspectRatio(aspectRatio, contentMode: .fit)
					.accessibilityElement()
					.accessibilityLabel("Radio screen")
			} else {
				Color.black
					.aspectRatio(aspectRatio, contentMode: .fit)
					.overlay {
						VStack(spacing: 8) {
							ProgressView()
								.tint(.white)
							Text("Waiting for the radio's screen")
								.font(.footnote)
								.foregroundStyle(.white)
						}
					}
			}
		}
		.padding(10)
		.background(.black, in: RoundedRectangle(cornerRadius: 12))
	}

	private var details: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(panelDescription)
				.font(.footnote)
				.foregroundStyle(.secondary)
			if isEInk {
				Text("E-ink screens redraw slowly. Tap Refresh for the latest picture.")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			Button {
				Task { await accessoryManager.requestDisplayFrame() }
			} label: {
				Label("Refresh", systemImage: "arrow.clockwise")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.roundedRectangle)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var panelDescription: String {
		let size = "\(metadata.displayWidth) × \(metadata.displayHeight)"
		switch DisplayInfo.PanelClass(rawValue: Int(metadata.displayPanelClass)) {
		case .oled: return String(localized: "\(size) OLED")
		case .lcd: return String(localized: "\(size) LCD")
		case .tft: return String(localized: "\(size) TFT")
		case .eink: return String(localized: "\(size) E-ink")
		case .hub75: return String(localized: "\(size) LED matrix")
		default: return size
		}
	}

	private func startIfVisible() async {
		guard accessoryManager.isConnected, scenePhase == .active else { return }
		await accessoryManager.startDisplayMirror()
	}
}
