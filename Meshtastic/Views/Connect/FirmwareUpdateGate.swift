//
//  FirmwareUpdateGate.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/7/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Full-screen gate shown while the connected radio's firmware is below the minimum the app
/// supports. The radio stays connected so the user can update it from here; the rest of the
/// app is blocked. The only ways out are a successful update or disconnecting.
struct FirmwareUpdateGate: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	/// The radio this window works with (feature 021, D-19).
	@Environment(\.windowRadio) private var windowRadio
	@Environment(\.modelContext) private var context

	@State private var node: NodeInfoEntity?

	var body: some View {
		NavigationStack {
			Firmware(node: node)
				.safeAreaInset(edge: .top) {
					VStack(spacing: 0) {
						RadioNameBanner()
						header
					}
				}
				.navigationTitle("Update Your Firmware")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) {
						Button("Disconnect", role: .destructive) {
							// The other radios stay as they are (feature 021, D-19).
							if let deviceId = accessoryManager.session(for: windowRadio)?.device.id {
								Task { await accessoryManager.disconnectRadio(deviceId) }
							}
						}
					}
				}
		}
		.interactiveDismissDisabled()
		.onAppear(perform: resolveNode)
		.onChange(of: accessoryManager.nodeNum(for: windowRadio)) { _, _ in resolveNode() }
	}

	private var header: some View {
		Label {
			Text("Firmware \(accessoryManager.session(for: windowRadio)?.device.firmwareVersion ?? "?.?.?") is no longer supported. Version \(accessoryManager.minimumVersion) or later is required to use the app. The radio stays connected so you can update it here.")
				.font(.callout)
		} icon: {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.orange)
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(.regularMaterial)
	}

	private func resolveNode() {
		// Bound to a local first: a #Predicate that reaches through self throws at fetch time
		// and the failure is silent.
		guard let num = accessoryManager.nodeNum(for: windowRadio) else {
			node = nil
			return
		}
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		do {
			node = try context.fetch(descriptor).first
		} catch {
			Logger.data.error("Could not load the connected node for the firmware update gate: \(error.localizedDescription, privacy: .public)")
			node = nil
		}
	}
}
