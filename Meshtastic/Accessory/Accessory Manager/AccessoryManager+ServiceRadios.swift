//
//  AccessoryManager+ServiceRadios.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import SwiftData

/// A service that works through one radio (D-12, T102): with several radios known, the radio the
/// user must choose for it while it's in use (W-15); with one, that radio.
enum RadioService: String, CaseIterable, Identifiable {
	/// The TAK bridge: CoT from TAK clients goes out through this radio.
	case tak
	/// CarPlay and Siri: messages sent from the car or by voice, and the lists CarPlay shows.
	case carPlay
	/// Apple Watch: which radio's view of nearby nodes it shows.
	case watch

	var id: String { rawValue }

	var label: String {
		switch self {
		case .tak: return "TAK".localized
		case .carPlay: return "CarPlay & Siri".localized
		case .watch: return "Apple Watch".localized
		}
	}

	var systemImage: String {
		switch self {
		case .tak: return "shield.lefthalf.filled"
		case .carPlay: return "car"
		case .watch: return "applewatch"
		}
	}

	fileprivate var defaultsKey: String { "serviceRadio.\(rawValue)" }
}

extension RadioService {
	/// In use, so it must have a radio chosen once two or more radios are known (W-15): TAK while
	/// its server is on, the Watch with a paired watch that has the app, CarPlay & Siri always.
	@MainActor
	var isInUse: Bool {
		switch self {
		case .tak: return TAKServerManager.shared.enabled
		case .watch: return WatchSessionManager.shared.isWatchAvailable
		case .carPlay: return true
		}
	}
}

extension UserDefaults {
	/// The radio chosen for `service`, 0 for none.
	static func serviceRadio(_ service: RadioService, in store: UserDefaults = .standard) -> Int64 {
		(store.object(forKey: service.defaultsKey) as? NSNumber)?.int64Value ?? 0
	}

	static func setServiceRadio(_ radioNum: Int64, for service: RadioService, in store: UserDefaults = .standard) {
		if radioNum == 0 {
			store.removeObject(forKey: service.defaultsKey)
		} else {
			store.set(radioNum, forKey: service.defaultsKey)
		}
	}
}

extension AccessoryManager {

	/// Two or more of the user's radios are known (connected with this version): each service
	/// in use then needs a radio chosen for it (W-15). With one, every service uses it, as on
	/// `main`.
	var hasSeveralRadios: Bool {
		knownRadios.count > 1
	}

	/// `knownRadios` with the connected ones first, as the choice sheet lists them (W-15).
	var knownRadiosConnectedFirst: [StoredRadio] {
		let connected = knownRadios.filter { isRadioConnected(nodeNum: $0.nodeNum) }
		return connected + knownRadios.filter { !isRadioConnected(nodeNum: $0.nodeNum) }
	}

	/// The radio `service` works with (W-15): with several radios known, the one chosen for it,
	/// also while it's off (a service waits for its radio, never using another), or nil until one
	/// is chosen; with one, the radio that's connected.
	func radioNum(for service: RadioService, store: UserDefaults = .standard) -> Int64? {
		guard hasSeveralRadios else {
			return activeConnection?.nodeNum ?? additionalRadios.values.first { $0.device.connectionState == .connected }?.nodeNum
		}
		let chosen = UserDefaults.serviceRadio(service, in: store)
		return chosen != 0 && knownRadios.contains { $0.nodeNum == chosen } ? chosen : nil
	}

	/// The connected session of `radioNum(for:)`: nil while that radio is off or none is chosen.
	func session(for service: RadioService, store: UserDefaults = .standard) -> RadioSession? {
		radioNum(for: service, store: store).flatMap { connectedSession(forRadio: $0) }
	}

	/// The services in use with no radio chosen, while several radios are known: the app asks
	/// for them (`ServiceRadioChoiceSheet`, W-15). `inUse` is for tests.
	func servicesNeedingRadio(store: UserDefaults = .standard, inUse: ((RadioService) -> Bool)? = nil) -> [RadioService] {
		guard hasSeveralRadios else { return [] }
		return RadioService.allCases.filter { (inUse?($0) ?? $0.isInUse) && radioNum(for: $0, store: store) == nil }
	}

	/// Makes `radioNum` the radio for `service`, and moves what follows it: TAK's channel, the
	/// Watch's nodes, the Messages sharing snapshot.
	func chooseServiceRadio(_ radioNum: Int64, for service: RadioService) {
		let previousTAKRadio = self.radioNum(for: .tak)
		UserDefaults.setServiceRadio(radioNum, for: service)
		objectWillChange.send()
		switch service {
		case .watch: WatchSessionManager.shared.sendNodesToWatch()
		case .tak:
			TAKServerManager.shared.moveChannel(from: previousTAKRadio, to: self.radioNum(for: .tak))
			TAKServerManager.shared.checkPrimaryChannelValidity()
		case .carPlay: refreshShareSnapshot()
		}
	}

	/// Radio `radioNum` was removed: every choice of it is cleared, so a service in use asks for
	/// another when several radios remain (W-15).
	func clearServiceRadios(pointingAt radioNum: Int64, store: UserDefaults = .standard) {
		for service in RadioService.allCases where UserDefaults.serviceRadio(service, in: store) == radioNum {
			UserDefaults.setServiceRadio(0, for: service, in: store)
		}
	}

	/// Reloads `knownRadios` from the store: at launch, after a connect and after a removal. With
	/// it, the device each radio last connected on (`radioLastDeviceIds`).
	func refreshKnownRadios() async {
		let radios = await MeshPackets.shared.radiosConnectedWithThisVersion()
		var lastDeviceIds: [Int64: UUID] = [:]
		for (peripheralId, nodeNum) in await MeshPackets.shared.radioPeripheralIds() {
			if let id = UUID(uuidString: peripheralId) {
				lastDeviceIds[nodeNum] = id
			}
		}
		if lastDeviceIds != radioLastDeviceIds {
			radioLastDeviceIds = lastDeviceIds
		}
		if radios != knownRadios {
			knownRadios = radios
		}
	}

	/// Refreshes the Messages sharing snapshot for the CarPlay & Siri radio, after that choice
	/// changes (T321).
	func refreshShareSnapshot() {
		guard let radioNum = radioNum(for: .carPlay) else { return }
		MeshShareSnapshotBuilder.refresh(nodeNum: radioNum, context: context)
	}

	/// The radio a Siri or Shortcuts command acts on (W-10, W-15): the one it names; else, with
	/// one radio, that radio; else the radio chosen for CarPlay & Siri. A radio named or chosen
	/// that's off is never swapped for another (`notConnected`); with none chosen yet the command
	/// asks which (`needsChoice`).
	func intentRadio(_ requested: Int64?, store: UserDefaults = .standard) -> IntentRadioChoice {
		if let requested {
			return isRadioConnected(nodeNum: requested) ? .radio(requested) : .notConnected
		}
		guard connectedRadioCount > 0 else { return .noRadio }
		guard hasSeveralRadios else {
			return radioNum(for: .carPlay, store: store).map { .radio($0) } ?? .noRadio
		}
		guard let chosen = radioNum(for: .carPlay, store: store) else { return .needsChoice }
		return isRadioConnected(nodeNum: chosen) ? .radio(chosen) : .notConnected
	}
}

/// Which radio a Siri or Shortcuts command acts on (`AccessoryManager.intentRadio`).
enum IntentRadioChoice: Equatable {
	case radio(Int64)
	/// The named radio isn't connected.
	case notConnected
	/// Several radios are connected and none is the default: the command asks which.
	case needsChoice
	/// No radio is connected.
	case noRadio

	/// The radio's node number, or the error for the command to throw: `noRadio` when nothing is
	/// connected, `notConnected` when the radio named or chosen is off (an error, not a new
	/// question, review V10 R10-7), `needsValue` so Siri or Shortcuts asks when none is chosen.
	func radioNum(noRadio: @autoclosure () -> Error, notConnected: @autoclosure () -> Error, needsValue: @autoclosure () -> Error) throws -> Int64 {
		switch self {
		case .radio(let radioNum): return radioNum
		case .noRadio: throw noRadio()
		case .notConnected: throw notConnected()
		case .needsChoice: throw needsValue()
		}
	}
}
