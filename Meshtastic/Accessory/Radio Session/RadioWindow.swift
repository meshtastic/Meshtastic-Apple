//
//  RadioWindow.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import MeshtasticProtobufs
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

	/// Whether `window`'s radio is connected, as `isConnected` counts it for the focused radio.
	func isConnected(_ window: RadioWindow) -> Bool {
		guard window.deviceId != nil else { return isConnected }
		return linkStatus(for: window).isConnected
	}

	/// Whether `window`'s radio is connecting, as `isConnecting` counts it for the focused radio.
	func isConnecting(_ window: RadioWindow) -> Bool {
		guard window.deviceId != nil else { return isConnecting }
		return linkStatus(for: window).isConnecting
	}

	/// The node number of `window`'s radio, also while it's disconnected. For `.focused` the
	/// preferred radio's, `PreferredRadio.nodeNum`.
	func radioNodeNum(for window: RadioWindow) -> Int64 {
		guard window.deviceId != nil else { return PreferredRadio.nodeNum }
		return session(for: window)?.nodeNum ?? 0
	}

	/// The peripheral id of `window`'s radio. For `.focused`, `PreferredRadio.peripheralId`.
	func radioPeripheralId(for window: RadioWindow) -> String {
		window.deviceId?.uuidString ?? PreferredRadio.peripheralId
	}

	/// What `window`'s radio reported: its firmware edition, version and region presets. For
	/// `.focused`, the manager's `firmwareEdition`, `connectedVersion` and `loRaRegionPresets`.
	func firmwareEdition(for window: RadioWindow) -> FirmwareEditions {
		session(for: window)?.firmwareEdition ?? .vanilla
	}

	func firmwareVersion(for window: RadioWindow) -> String? {
		session(for: window)?.device.firmwareVersion
	}

	func loRaRegionPresets(for window: RadioWindow) -> [Config.LoRaConfig.RegionCode: RegionPresetInfo] {
		session(for: window)?.loRaRegionPresets ?? [:]
	}

	/// When `window`'s radio last finished sending its configuration. For `.focused`,
	/// `lastConfigRefresh`.
	func lastConfigRefresh(for window: RadioWindow) -> Date? {
		guard window.deviceId != nil else { return lastConfigRefresh }
		return session(for: window)?.lastConfigRefresh
	}

	/// `window`'s radio's MQTT client proxy. For `.focused`, `mqttProxyConnected` and `mqttTopics`.
	func mqttProxyConnected(for window: RadioWindow) -> Bool {
		session(for: window)?.mqtt?.isConnected ?? false
	}

	func mqttTopics(for window: RadioWindow) -> [String] {
		session(for: window)?.mqtt?.topics ?? []
	}

	/// `checkIsVersionSupported` for `window`'s radio: its own reported firmware
	/// (`isVersionSupported(forVersion:on:)`); for `.focused`, exactly `checkIsVersionSupported`.
	func isVersionSupported(forVersion version: String, for window: RadioWindow) -> Bool {
		guard window.deviceId != nil, let session = session(for: window) else { return checkIsVersionSupported(forVersion: version) }
		return isVersionSupported(forVersion: version, on: session)
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

/// Gives a window's views its radio's lock-down state (feature 021, T301): the passphrase sheet,
/// Settings' lock-down section and the gates that wait on it follow the window's radio. Lock Now
/// acknowledged is handled by the manager (`lockdownStateChanged`).
struct WindowLockdownScope: ViewModifier {
	@ObservedObject private var accessoryManager = AccessoryManager.shared
	@Environment(\.windowRadio) private var windowRadio

	func body(content: Content) -> some View {
		content.environmentObject(accessoryManager.session(for: windowRadio)?.lockdown ?? LockdownCoordinator.noRadio)
	}
}
