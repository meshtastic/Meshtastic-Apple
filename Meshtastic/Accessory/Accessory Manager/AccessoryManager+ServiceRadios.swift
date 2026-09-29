//
//  AccessoryManager+ServiceRadios.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import SwiftData

/// A service that works through one radio (D-12, T102): the radio the user picks for it in App
/// Settings, else the radio connected first (T321).
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

/// Whether to make a radio that just connected the one Siri and CarPlay use (W-09, T319).
struct ServiceRadioQuestion: Identifiable, Equatable {
	/// The radio's device id.
	let id: UUID
	let nodeNum: Int64
	let radioName: String
}

extension UserDefaults {
	/// The radio chosen for `service`, 0 to follow the focused radio.
	static func serviceRadio(_ service: RadioService, in store: UserDefaults = .standard) -> Int64 {
		(store.object(forKey: service.defaultsKey) as? NSNumber)?.int64Value ?? 0
	}

	/// The radios already asked about for Siri and CarPlay (T319): each is asked once.
	static func askedServiceRadios(in store: UserDefaults = .standard) -> Set<Int64> {
		Set((store.array(forKey: "multiRadio.askedServiceRadios") as? [NSNumber] ?? []).map(\.int64Value))
	}

	static func setAskedServiceRadios(_ radios: Set<Int64>, in store: UserDefaults = .standard) {
		store.set(radios.sorted().map { NSNumber(value: $0) }, forKey: "multiRadio.askedServiceRadios")
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

	/// The connected radio `service` uses (T321): the one chosen for it while that radio is
	/// connected, otherwise the radio the app connected first, otherwise the one that's connected.
	/// Nil with no radio connected. With one radio, that radio.
	func session(for service: RadioService, store: UserDefaults = .standard) -> RadioSession? {
		let chosen = UserDefaults.serviceRadio(service, in: store)
		if chosen != 0, let session = connectedSession(forRadio: chosen) {
			return session
		}
		return activeConnection
			?? additionalRadios.values.first { $0.device.connectionState == .connected }
			?? additionalRadios.values.first
	}

	/// The node number of `session(for:)`.
	func radioNum(for service: RadioService, store: UserDefaults = .standard) -> Int64? {
		session(for: service, store: store)?.nodeNum
	}

	/// Refreshes the Messages sharing snapshot for the CarPlay & Siri radio, after that choice
	/// changes (T321).
	func refreshShareSnapshot() {
		guard let radioNum = radioNum(for: .carPlay) else { return }
		MeshShareSnapshotBuilder.refresh(nodeNum: radioNum, context: context)
	}

	/// Whether to ask about radio `radioNum`, just connected, for Siri and CarPlay (W-09): once
	/// per radio, only when another of the user's radios is known (so never with one radio), and
	/// not when it's already the one.
	static func shouldAskAboutServiceRadio(_ radioNum: Int64, otherRadiosKnown: Bool, store: UserDefaults = .standard) -> Bool {
		otherRadiosKnown
			&& UserDefaults.serviceRadio(.carPlay, in: store) != radioNum
			&& !UserDefaults.askedServiceRadios(in: store).contains(radioNum)
	}

	/// After `session`'s connect: asks, once, whether it should be the Siri and CarPlay radio.
	/// While another radio's question is up, this one waits for its next connect.
	func askAboutServiceRadioIfNeeded(_ session: RadioSession) async {
		guard serviceRadioQuestion == nil, let radioNum = session.nodeNum else { return }
		let otherRadiosKnown = await MeshPackets.shared.storedRadios().contains { $0.nodeNum != radioNum }
		guard Self.shouldAskAboutServiceRadio(radioNum, otherRadiosKnown: otherRadiosKnown) else { return }
		UserDefaults.setAskedServiceRadios(UserDefaults.askedServiceRadios().union([radioNum]))
		serviceRadioQuestion = ServiceRadioQuestion(id: session.device.id, nodeNum: radioNum, radioName: session.device.longName ?? session.device.name)
	}

	/// The radio a Siri or Shortcuts command acts on (W-10, T320, T321): the one it names, else
	/// the radio chosen for CarPlay & Siri while it's connected, else the only radio connected.
	/// With several connected and none of those, the command asks which (`needsChoice`). A named
	/// radio that isn't connected is never swapped for another (`notConnected`).
	func intentRadio(_ requested: Int64?, store: UserDefaults = .standard) -> IntentRadioChoice {
		if let requested {
			return isRadioConnected(nodeNum: requested) ? .radio(requested) : .notConnected
		}
		let chosen = UserDefaults.serviceRadio(.carPlay, in: store)
		if chosen != 0, isRadioConnected(nodeNum: chosen) {
			return .radio(chosen)
		}
		let connected = connectedRadioNums
		switch connected.count {
		case 0: return .noRadio
		case 1: return .radio(connected[0])
		default: return .needsChoice
		}
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
	/// connected, else `needsValue` so Siri or Shortcuts asks for a radio.
	func radioNum(noRadio: @autoclosure () -> Error, needsValue: @autoclosure () -> Error) throws -> Int64 {
		switch self {
		case .radio(let radioNum): return radioNum
		case .noRadio: throw noRadio()
		case .notConnected, .needsChoice: throw needsValue()
		}
	}
}
