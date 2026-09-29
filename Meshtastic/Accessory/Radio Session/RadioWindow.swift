//
//  RadioWindow.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// The radio a window works with (feature 021, D-19): every screen in the window shows that
/// radio's settings, messages and connection. Named by its device id (its peripheral id), which
/// is known before its node number.
///
/// Until windows have their own radio (T310), there's one window and it follows the focused
/// radio: `.focused`, whose lookups answer exactly as the manager's focused-radio properties do.
struct RadioWindow: Codable, Hashable, Sendable {
	/// The radio's device id; nil is the focused radio.
	var deviceId: UUID?

	static let focused = RadioWindow(deviceId: nil)
}

private struct WindowRadioKey: EnvironmentKey {
	static let defaultValue = RadioWindow.focused
}

extension EnvironmentValues {
	/// The radio of the window this view is in.
	var windowRadio: RadioWindow {
		get { self[WindowRadioKey.self] }
		set { self[WindowRadioKey.self] = newValue }
	}
}

extension AccessoryManager {

	/// The connected session of `window`'s radio, if it's connected.
	func session(for window: RadioWindow) -> RadioSession? {
		guard let deviceId = window.deviceId else { return activeConnection }
		if activeConnection?.device.id == deviceId {
			return activeConnection
		}
		return additionalRadios[deviceId]
	}

	/// The node number of `window`'s radio while it's connected; nil otherwise. For `.focused`
	/// it's `activeDeviceNum`.
	func nodeNum(for window: RadioWindow) -> Int64? {
		guard window.deviceId != nil else { return activeDeviceNum }
		return session(for: window)?.nodeNum
	}

	/// Whether `window`'s radio is connected.
	func isConnected(_ window: RadioWindow) -> Bool {
		guard window.deviceId != nil else { return isConnected }
		return session(for: window)?.device.connectionState == .connected
	}

	/// `window`'s radio's connection (`linkStatus(of:)`). For `.focused` with no radio at all,
	/// the manager's own state.
	func linkStatus(for window: RadioWindow) -> RadioLinkStatus {
		if let deviceId = window.deviceId ?? focusedDeviceId {
			return linkStatus(of: deviceId)
		}
		return RadioLinkStatus(state: state, canDisconnect: allowDisconnect, attention: nil, lastError: lastConnectionError)
	}
}
