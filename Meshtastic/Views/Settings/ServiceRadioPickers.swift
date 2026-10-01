//
//  ServiceRadioPickers.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// App Settings pickers for the radio TAK, CarPlay & Siri and the Apple Watch use (feature 021,
/// T102, W-15). Only shown once more than one radio is known; with one, every service uses it.
struct ServiceRadioPickers: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	var body: some View {
		if accessoryManager.hasSeveralRadios {
			ForEach(RadioService.allCases) { service in
				Picker(selection: binding(for: service)) {
					if accessoryManager.radioNum(for: service) == nil {
						Text("Not Set").tag(Int64(0))
					}
					ForEach(accessoryManager.knownRadios, id: \.nodeNum) { radio in
						Text(radioName(radio)).tag(radio.nodeNum)
					}
				} label: {
					Label(service.label, systemImage: service.systemImage)
				}
			}
			Text("Which radio TAK, CarPlay & Siri and the Apple Watch use. A service in use must have one; while its radio is off it waits for it.")
				.foregroundStyle(.secondary)
				.font(.caption)
		}
	}

	private func binding(for service: RadioService) -> Binding<Int64> {
		Binding(get: { accessoryManager.radioNum(for: service) ?? 0 }, set: { newValue in
			guard newValue != 0 else { return }
			accessoryManager.chooseServiceRadio(newValue, for: service)
		})
	}

	private func radioName(_ radio: StoredRadio) -> String {
		if let device = accessoryManager.connectedSession(forRadio: radio.nodeNum)?.device {
			return device.shortName ?? device.longName ?? device.name
		}
		return radio.name
	}
}

/// Makes the user choose a radio for each service in use once several radios are known (W-15):
/// CarPlay & Siri always, TAK while its server is on, the Watch with one paired. It only closes
/// once each has a radio; TAK can be turned off instead.
struct ServiceRadioChoiceSheet: View {
	@ObservedObject private var accessoryManager = AccessoryManager.shared
	@ObservedObject private var tak = TAKServerManager.shared
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		let needed = accessoryManager.servicesNeedingRadio()
		NavigationStack {
			Form {
				Section {
					Text("You have more than one radio. Choose the one each of these uses; you can change it later in App Settings.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
				ForEach(needed) { service in
					Section {
						ForEach(accessoryManager.knownRadiosConnectedFirst, id: \.nodeNum) { radio in
							Button {
								accessoryManager.chooseServiceRadio(radio.nodeNum, for: service)
							} label: {
								Label(radio.name, systemImage: accessoryManager.isRadioConnected(nodeNum: radio.nodeNum) ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
							}
						}
						if service == .tak {
							Button("Turn TAK Off Instead", role: .destructive) {
								tak.enabled = false
								accessoryManager.objectWillChange.send()
							}
						}
					} header: {
						Label(service.label, systemImage: service.systemImage)
					}
				}
			}
			.navigationTitle("Choose Radios")
			.navigationBarTitleDisplayMode(.inline)
		}
		.interactiveDismissDisabled(true)
		.onChange(of: needed.isEmpty) { _, done in
			if done { dismiss() }
		}
	}
}

/// Shows `ServiceRadioChoiceSheet` while a service in use has no radio (W-15). Mirrored into
/// view state, as ContentView's gates are, so the presentation binding is plain state.
///
/// A view presents one sheet, cover or alert at a time, and one asked for while another is up can
/// be lost (T359). So the sheet waits while `waits` says something else of the view is up, and
/// comes up a moment after it closes; `isUp` tells the view it's up until it has closed, so what
/// waits for it comes after, and `onClose` runs then. A sheet asked for that doesn't come up (a
/// sheet opened further in is up) is asked for again, and keeps its turn meanwhile, so nothing
/// else is asked for while the window can't show it either (review V12 R12-1, V13 R13-1).
struct ServiceRadioChoiceGate: ViewModifier {
	@ObservedObject private var accessoryManager = AccessoryManager.shared
	@ObservedObject private var tak = TAKServerManager.shared
	@State private var isShowing = false
	/// The sheet is on screen, from its appearing to its dismissal.
	@State private var isVisible = false
	/// Its turn: from being asked for until it has come up and closed, or the choice is made
	/// elsewhere. Kept here as well as in `isUp`, which can be a constant.
	@State private var holdsTurn = false
	@State private var isWaiting = false
	var waits: Bool
	@Binding var isUp: Bool
	var onClose: () -> Void

	init(waits: Bool = false, isUp: Binding<Bool> = .constant(false), onClose: @escaping () -> Void = {}) {
		self.waits = waits
		self._isUp = isUp
		self.onClose = onClose
	}

	func body(content: Content) -> some View {
		let needsChoice = !accessoryManager.servicesNeedingRadio().isEmpty
		content
			.onAppear {
				isWaiting = waits
				update(needsChoice: needsChoice)
			}
			.onChange(of: needsChoice) { _, needed in update(needsChoice: needed) }
			.onChange(of: waits) { _, waiting in
				isWaiting = waiting
				update(needsChoice: needsChoice)
			}
			.sheet(isPresented: $isShowing, onDismiss: {
				// Only a sheet that came up ends its turn by closing; one that didn't is asked for
				// again (review V13 R13-1).
				guard isVisible else { return }
				isVisible = false
				release()
			}) {
				ServiceRadioChoiceSheet()
					.onAppear { isVisible = true }
			}
	}

	/// Once up it stays until each service has a radio. It comes up only with nothing else up, a
	/// moment later so what just closed is gone first (as the attention prompts do).
	private func update(needsChoice: Bool) {
		guard needsChoice else {
			// Chosen elsewhere (App Settings) while the sheet wasn't up: its turn ends here. One
			// that's up closes, and ends it when it has.
			if holdsTurn, !isVisible {
				release()
			}
			isShowing = false
			return
		}
		guard !isShowing, !isWaiting else { return }
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(600))
			guard !isShowing, !isWaiting, !accessoryManager.servicesNeedingRadio().isEmpty else { return }
			holdsTurn = true
			isUp = true
			isShowing = true
			// Not shown while a sheet opened further in is up, and not shown later either (review V12
			// R12-1): asked for again in a moment, keeping its turn (review V13 R13-1).
			try? await Task.sleep(for: .seconds(2))
			guard holdsTurn, !isVisible else { return }
			isShowing = false
			try? await Task.sleep(for: .seconds(2))
			update(needsChoice: !accessoryManager.servicesNeedingRadio().isEmpty)
		}
	}

	/// Its turn is over: what waited for it can come.
	private func release() {
		holdsTurn = false
		isUp = false
		onClose()
	}
}
