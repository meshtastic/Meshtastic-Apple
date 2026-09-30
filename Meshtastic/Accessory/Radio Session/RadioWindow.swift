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

/// Whether each radio gets its own window (feature 021, D-19): on the Mac. iPhone and iPad keep
/// one window that switches between radios (W-04; iPad decided 2026-09-29).
enum RadioWindows {
	static var areEnabled: Bool { ProcessInfo.processInfo.isMacCatalystApp }
	/// A radio's window (`WindowGroup(for: RadioWindow.self)`).
	static let radioWindowID = "radio-window"
	/// The Connect window on the Mac, and the one window elsewhere.
	static let mainWindowID = "main"
}

private struct WindowRadioKey: EnvironmentKey {
	static let defaultValue = RadioWindow.focused
}

/// Shows another connected radio in this window (W-13): on iPhone and iPad the one window
/// switches to it, without disconnecting anything; on the Mac its own window opens.
struct SelectWindowRadioAction {
	let select: @MainActor (UUID) -> Void

	@MainActor
	func callAsFunction(_ deviceId: UUID) {
		select(deviceId)
	}
}

private struct SelectWindowRadioKey: EnvironmentKey {
	static let defaultValue = SelectWindowRadioAction { _ in }
}

extension EnvironmentValues {
	/// The radio of the window this view is in.
	var windowRadio: RadioWindow {
		get { self[WindowRadioKey.self] }
		set { self[WindowRadioKey.self] = newValue }
	}

	/// Shows another radio in this window (W-13).
	var selectWindowRadio: SelectWindowRadioAction {
		get { self[SelectWindowRadioKey.self] }
		set { self[SelectWindowRadioKey.self] = newValue }
	}
}

/// The one window on iPhone and iPad (W-04): shows the radio the user last picked, kept with the
/// window, and switches when they pick another (T314, T324). With one radio the user never picks
/// one, so the window follows the radio the app connects, as before.
struct OneWindowRadioScope<Content: View>: View {
	@SceneStorage("windowRadioId") private var storedId = ""
	@ObservedObject private var accessoryManager = AccessoryManager.shared
	@ViewBuilder let content: () -> Content

	var body: some View {
		let window = accessoryManager.oneWindowRadio(stored: UUID(uuidString: storedId))
		content()
			.modifier(WindowLockdownScope())
			.environment(\.windowRadio, window)
			.environment(\.selectWindowRadio, SelectWindowRadioAction { storedId = $0.uuidString })
			.onChange(of: accessoryManager.session(for: window)?.device.id, initial: true) { _, shown in
				accessoryManager.oneWindowShownRadio = shown
			}
	}
}

extension AccessoryManager {

	/// What the one window shows (iPhone, iPad; W-04), given the radio the user last picked
	/// (`stored`): that radio while it's connected, connecting or being brought back; otherwise the
	/// radio the app connects first (`.focused`), or, when the user disconnected that one and
	/// another is still connected, the other one.
	func oneWindowRadio(stored: UUID?) -> RadioWindow {
		if let stored, stored != activeConnection?.device.id,
		   isRadioConnected(stored) || connectAttempts[stored] != nil || additionalRadioReconnects[stored] != nil {
			return RadioWindow(deviceId: stored)
		}
		if activeConnection == nil, userRequestedConnectionCancellation,
		   let other = additionalRadios.values.first(where: { $0.device.connectionState == .connected }) {
			return RadioWindow(deviceId: other.device.id)
		}
		return .focused
	}

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

	/// The radio a window's sends go through: nil, the radio connected first, for `.focused`;
	/// otherwise the window's own radio, so a send while it's disconnected fails rather than going
	/// through another radio (review V11 X1).
	func sendingRadio(for window: RadioWindow) -> Int64? {
		guard window.deviceId != nil else { return nil }
		return radioNodeNum(for: window)
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

	/// Whether `window`'s radio's firmware is below the minimum, which puts the update gate over
	/// the window. For `.focused`, `firmwareUpdateRequired`.
	func firmwareUpdateRequired(for window: RadioWindow) -> Bool {
		guard window.deviceId != nil else { return firmwareUpdateRequired }
		return linkStatus(for: window).firmwareUpdateRequired
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
