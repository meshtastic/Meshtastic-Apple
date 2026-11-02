//
//  RadioSetupFlow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//
//  The guided setup for a connected radio: region, preset and name. Opens on its own the
//  first time a radio with no region connects, and from the Set Up Radio rows on Connect and
//  Settings.
//

import SwiftData
import SwiftUI

/// Which radio to set up; presenting one of these opens the flow.
struct RadioSetupRequest: Identifiable {
	let nodeNum: Int64
	var id: Int64 { nodeNum }
}

private struct OpenRadioSetupKey: EnvironmentKey {
	static let defaultValue: (Int64) -> Void = { _ in }
}

extension EnvironmentValues {
	/// Opens the radio setup flow for a node number. ContentView provides it.
	var openRadioSetup: (Int64) -> Void {
		get { self[OpenRadioSetupKey.self] }
		set { self[OpenRadioSetupKey.self] = newValue }
	}
}

struct RadioSetupFlow: View {
	let nodeNum: Int64
	/// Closes the flow where it isn't a sheet, like on the cinema's screen. Nil dismisses.
	var onClose: (() -> Void)?

	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@State private var model: RadioSetupModel?
	@State private var hasLoaded = false

	var body: some View {
		Group {
			if let model {
				RadioSetupPages(model: model, onFinished: close)
			} else if hasLoaded {
				// The node is not in the store, which only happens when a reset emptied it.
				ContentUnavailableView {
					Label("Radio Not Found", systemImage: "antenna.radiowaves.left.and.right.slash")
				} actions: {
					Button("Close", action: close)
				}
			} else {
				ProgressView()
			}
		}
		.onAppear {
			guard !hasLoaded else { return }
			model = RadioSetupModel(nodeNum: nodeNum, context: context, accessoryManager: accessoryManager)
			hasLoaded = true
		}
		// A different radio took over mid-flow; its settings are not the ones on screen.
		.onChange(of: accessoryManager.activeDeviceNum) { _, num in
			if let num, num != nodeNum { close() }
		}
		.onChange(of: accessoryManager.state) { _, state in
			if state == .subscribed { model?.isAwaitingReconnect = false }
		}
		.interactiveDismissDisabled(model?.isSaving == true)
	}

	private func close() {
		if let onClose { onClose() } else { dismiss() }
	}
}

/// The pages on a navigation stack driven by the model's `path`. Apart from the flow so
/// snapshots can render it from plain values.
struct RadioSetupPages: View {
	@Bindable var model: RadioSetupModel
	let onFinished: () -> Void

	var body: some View {
		NavigationStack(path: $model.path) {
			// The root hides its bar and pads the same height, so its title sits where the
			// pushed pages' titles sit under their back button.
			RadioSetupIntroPage(model: model, onNotNow: onFinished)
				.padding(.top, 44)
				.toolbar(.hidden, for: .navigationBar)
				.trackScreen(RadioSetupStep.intro.screenName)
				.navigationDestination(for: RadioSetupStep.self) { step in
					Group {
						switch step {
						case .intro:
							RadioSetupIntroPage(model: model, onNotNow: onFinished)
						case .region:
							RadioSetupRegionPage(model: model)
						case .preset:
							RadioSetupPresetPage(model: model)
						case .name:
							RadioSetupNamePage(model: model)
						case .done:
							RadioSetupDonePage(model: model, onDone: onFinished)
						}
					}
					.navigationBarTitleDisplayMode(.inline)
					.trackScreen(step.screenName)
				}
		}
	}
}
