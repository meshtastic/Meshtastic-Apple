//
//  ServiceRadioPickers.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftData
import SwiftUI

/// App Settings pickers for the radio TAK, CarPlay & Siri and the Apple Watch use (feature 021,
/// T102). Only shown once the user has more than one radio; with one, every service uses it.
struct ServiceRadioPickers: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Query(sort: \MyInfoEntity.myNodeNum) private var radios: [MyInfoEntity]
	@State private var choices: [RadioService: Int64] = Dictionary(
		uniqueKeysWithValues: RadioService.allCases.map { ($0, UserDefaults.serviceRadio($0)) }
	)

	var body: some View {
		let radioNums = radios.map(\.myNodeNum).filter { $0 != 0 }
		if radioNums.count > 1 {
			ForEach(RadioService.allCases) { service in
				Picker(selection: binding(for: service)) {
					Text("Automatic").tag(Int64(0))
					ForEach(radioNums, id: \.self) { radioNum in
						Text(radioName(radioNum)).tag(radioNum)
					}
				} label: {
					Label(service.label, systemImage: service.systemImage)
				}
			}
			.onAppear {
				// A radio the user has since removed would otherwise stay selected, unlisted.
				for service in RadioService.allCases where choices[service, default: 0] != 0 && !radioNums.contains(choices[service, default: 0]) {
					binding(for: service).wrappedValue = 0
				}
			}
			Text("Which radio TAK, CarPlay & Siri and the Apple Watch use. Automatic, or a chosen radio that isn't connected, uses the radio connected first; with several connected, Siri and Shortcuts ask which.")
				.foregroundStyle(.secondary)
				.font(.caption)
		}
	}

	private func binding(for service: RadioService) -> Binding<Int64> {
		Binding(get: { choices[service, default: 0] }, set: { newValue in
			let previousTAKRadio = accessoryManager.radioNum(for: .tak)
			choices[service] = newValue
			UserDefaults.setServiceRadio(newValue, for: service)
			switch service {
			case .watch: WatchSessionManager.shared.sendNodesToWatch()
			case .tak:
				TAKServerManager.shared.moveChannel(from: previousTAKRadio, to: accessoryManager.radioNum(for: .tak))
				TAKServerManager.shared.checkPrimaryChannelValidity()
			case .carPlay: accessoryManager.refreshShareSnapshot()
			}
		})
	}

	/// From the queried radios' relationships, not a fetch: this runs while the pickers render.
	private func radioName(_ radioNum: Int64) -> String {
		if let device = accessoryManager.connectedSession(forRadio: radioNum)?.device {
			return device.shortName ?? device.longName ?? device.name
		}
		let user = radios.first { $0.myNodeNum == radioNum }?.myInfoNode?.user
		return user?.longName ?? user?.shortName ?? radioNum.toHex()
	}
}

/// Asks once, when a radio connects and another is known, whether it should be the radio Siri,
/// CarPlay and Shortcuts use when a command doesn't name one (feature 021, W-09, T319).
struct ServiceRadioQuestionAlert: ViewModifier {
	@ObservedObject private var accessoryManager = AccessoryManager.shared

	func body(content: Content) -> some View {
		content.background(
			Color.clear.alert(item: $accessoryManager.serviceRadioQuestion) { question in
				Alert(
					title: Text("Use \(question.radioName) for Siri and CarPlay?"),
					message: Text("Siri, CarPlay and Shortcuts use it when a command doesn't name a radio. You can change it in App Settings."),
					primaryButton: .default(Text("Use \(question.radioName)")) {
						UserDefaults.setServiceRadio(question.nodeNum, for: .carPlay)
						accessoryManager.refreshShareSnapshot()
					},
					secondaryButton: .cancel(Text("Not Now"))
				)
			}
		)
	}
}
