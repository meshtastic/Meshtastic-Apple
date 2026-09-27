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
					Text("Follow Focused Radio").tag(Int64(0))
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
			Text("Which radio TAK, CarPlay & Siri and the Apple Watch use. A chosen radio that isn't connected falls back to the focused radio.")
				.foregroundStyle(.secondary)
				.font(.caption)
		}
	}

	private func binding(for service: RadioService) -> Binding<Int64> {
		Binding(get: { choices[service, default: 0] }, set: { newValue in
			choices[service] = newValue
			UserDefaults.setServiceRadio(newValue, for: service)
			switch service {
			case .watch: WatchSessionManager.shared.sendNodesToWatch()
			case .tak: TAKServerManager.shared.checkPrimaryChannelValidity()
			case .carPlay: break
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
