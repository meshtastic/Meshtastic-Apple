//
//  AccessoryManager+ServiceRadios.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import SwiftData

/// A service that works through one radio (D-12, T102). Each follows the focused radio unless
/// the user picks one of their radios for it in App Settings.
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

extension UserDefaults {
	/// The radio chosen for `service`, 0 to follow the focused radio.
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

	/// The connected radio `service` uses: the one chosen for it while that radio is connected,
	/// otherwise the focused radio. Nil with no radio connected.
	func session(for service: RadioService, store: UserDefaults = .standard) -> RadioSession? {
		let chosen = UserDefaults.serviceRadio(service, in: store)
		if chosen != 0, let session = connectedSession(forRadio: chosen) {
			return session
		}
		return activeConnection
	}

	/// The node number of `session(for:)`.
	func radioNum(for service: RadioService, store: UserDefaults = .standard) -> Int64? {
		session(for: service, store: store)?.nodeNum
	}

	/// The radio a Shortcuts send goes through (T104): the one the intent names, or the radio
	/// chosen for CarPlay & Siri when it names none. Nil when the named radio isn't connected,
	/// or nothing is: a message meant for one radio never goes out from another.
	func intentRadioNum(_ requested: Int?, store: UserDefaults = .standard) -> Int64? {
		guard let requested else { return radioNum(for: .carPlay, store: store) }
		return connectedSession(forRadio: Int64(requested))?.nodeNum
	}
}
