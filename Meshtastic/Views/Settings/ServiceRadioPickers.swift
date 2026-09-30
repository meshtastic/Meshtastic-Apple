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
struct ServiceRadioChoiceGate: ViewModifier {
	@ObservedObject private var accessoryManager = AccessoryManager.shared
	@ObservedObject private var tak = TAKServerManager.shared
	@State private var isShowing = false

	func body(content: Content) -> some View {
		let needsChoice = !accessoryManager.servicesNeedingRadio().isEmpty
		content
			.onAppear { isShowing = needsChoice }
			.onChange(of: needsChoice) { _, needed in isShowing = needed }
			.sheet(isPresented: $isShowing) {
				ServiceRadioChoiceSheet()
			}
	}
}
