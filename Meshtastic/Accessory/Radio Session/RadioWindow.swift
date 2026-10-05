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
/// `.firstRadio` is the window of the radio connected first, and its lookups answer exactly as the
/// manager's own properties do, so one radio's one window works as on `main`.
struct RadioWindow: Codable, Hashable, Sendable {
	/// The radio's device id; nil is the first radio.
	var deviceId: UUID?

	static let firstRadio = RadioWindow(deviceId: nil)
}

/// One of the user's radios that's off (W-02): its window shows it with Connect and Remove Radio,
/// and the Mac lists it with the connected radios.
struct OfflineRadio: Identifiable, Equatable, Sendable {
	/// The device it was last connected on.
	let deviceId: UUID
	let nodeNum: Int64
	let name: String

	var id: UUID { deviceId }
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
	static let defaultValue = RadioWindow.firstRadio
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
	/// The radio the window last showed with a session. A radio's Disconnect is told before its
	/// link closes, so a window showing it still has it here (review V28-1).
	@State private var lastShown: UUID?
	@ViewBuilder let content: () -> Content

	var body: some View {
		let window = accessoryManager.oneWindowRadio(stored: UUID(uuidString: storedId))
		content()
			.modifier(WindowLockdownScope())
			.environment(\.windowRadio, window)
			.environment(\.selectWindowRadio, SelectWindowRadioAction { storedId = $0.uuidString })
			.onChange(of: accessoryManager.session(for: window)?.device.id, initial: true) { _, shown in
				accessoryManager.oneWindowShownRadio = shown
				if let shown {
					lastShown = shown
				}
			}
			// With several radios, the window keeps the radio the user disconnected, shown off,
			// until they pick another (W-02); whichever Disconnect it was: the Connect tab's, the
			// update screen's or Shortcuts' (review V27-7).
			.onReceive(accessoryManager.radioDisconnectedByUser) { deviceId in
				if accessoryManager.hasSeveralRadios, deviceId == lastShown || deviceId == window.deviceId {
					storedId = deviceId.uuidString
				}
			}
	}
}

extension AccessoryManager {

	/// What the one window shows (iPhone, iPad; W-04), given the radio the user last picked
	/// (`stored`): that radio while it's one of theirs. Off, it shows off with Connect until they
	/// pick another (W-02); removed, it's gone. Otherwise the radio the app connects first
	/// (`.firstRadio`), or, when the user disconnected that one and another is still connected,
	/// the other one. A first radio released for a firmware update is still shown; another radio
	/// released for one isn't, as before W-02 (review V27-6).
	func oneWindowRadio(stored: UUID?) -> RadioWindow {
		if let stored, stored != activeConnection?.device.id {
			if isRadioConnected(stored) || connectAttempts[stored] != nil || additionalRadioReconnects[stored] != nil {
				return RadioWindow(deviceId: stored)
			}
			// Off. The radio the app connects first stays `.firstRadio`, as while it's released
			// for a firmware update or dropped, to come back. With several radios, one the user
			// disconnected shows off from the moment its link is gone, before `PreferredRadio`
			// moves to another radio, rather than that other radio for a moment (review V28-1).
			let userDisconnectedFirst = hasSeveralRadios && userRequestedConnectionCancellation && !firstRadioReleasedForUpdate
			if stored != firstDeviceId || userDisconnectedFirst, offlineRadio(stored) != nil {
				return RadioWindow(deviceId: stored)
			}
		}
		if activeConnection == nil, userRequestedConnectionCancellation, !firstRadioReleasedForUpdate,
		   let other = connectedRadioAfterFirst {
			return RadioWindow(deviceId: other.id)
		}
		return .firstRadio
	}

	/// The connected session of `window`'s radio, if it's connected.
	func session(for window: RadioWindow) -> RadioSession? {
		guard let deviceId = window.deviceId else { return activeConnection }
		if activeConnection?.device.id == deviceId {
			return activeConnection
		}
		return additionalRadios[deviceId]
	}

	/// The connected radios other than `window`'s, starting with the first radio: the ones the
	/// window can switch to, and the ones its Settings doesn't configure.
	func otherConnectedRadios(than window: RadioWindow) -> [Device] {
		let shown = session(for: window)?.device.id
		return connectedRadios.filter { $0.id != shown }
	}

	/// The node number of `window`'s radio while it's connected; nil otherwise. For `.firstRadio`
	/// it's `activeDeviceNum`.
	func nodeNum(for window: RadioWindow) -> Int64? {
		guard window.deviceId != nil else { return activeDeviceNum }
		return session(for: window)?.nodeNum
	}

	/// Whether `window`'s radio is connected, as `isConnected` counts it for the first radio.
	func isConnected(_ window: RadioWindow) -> Bool {
		guard window.deviceId != nil else { return isConnected }
		return linkStatus(for: window).isConnected
	}

	/// Whether `window`'s radio is connecting, as `isConnecting` counts it for the first radio.
	func isConnecting(_ window: RadioWindow) -> Bool {
		guard window.deviceId != nil else { return isConnecting }
		return linkStatus(for: window).isConnecting
	}

	/// The node number of `window`'s radio, also while it's disconnected. For `.firstRadio` the
	/// preferred radio's, `PreferredRadio.nodeNum`.
	func radioNodeNum(for window: RadioWindow) -> Int64 {
		guard let deviceId = window.deviceId else { return PreferredRadio.nodeNum }
		return session(for: window)?.nodeNum ?? knownNodeNums[deviceId] ?? 0
	}

	/// The radio a window's sends go through: nil, the radio connected first, for `.firstRadio`;
	/// otherwise the window's own radio, so a send while it's disconnected fails rather than going
	/// through another radio (review V11 X1).
	func sendingRadio(for window: RadioWindow) -> Int64? {
		guard window.deviceId != nil else { return nil }
		return radioNodeNum(for: window)
	}

	/// The device id of radio `radioNum`: its session's; else the one it last connected on, the
	/// store's `peripheralId`, which its window was opened for; else the first of the ones it's
	/// known by, in a fixed order. A radio known over BLE and TCP has one window (W-03, review
	/// V28 minor 2).
	func deviceId(ofRadio radioNum: Int64) -> UUID? {
		if let session = connectedSession(forRadio: radioNum) {
			return session.device.id
		}
		if let last = radioLastDeviceIds[radioNum], knownNodeNums[last] == radioNum {
			return last
		}
		return knownNodeNums.filter { $0.value == radioNum }.keys.min { $0.uuidString < $1.uuidString }
	}

	// MARK: - Radios that are off (W-02)

	/// The name of radio `deviceId`, connected or not: its long name while it's connected, else the
	/// name the store has for it, else what discovery calls it.
	func radioName(of deviceId: UUID) -> String? {
		if let device = connectedRadios.first(where: { $0.id == deviceId }) {
			return device.longName ?? device.name
		}
		if let num = knownNodeNums[deviceId], let known = knownRadios.first(where: { $0.nodeNum == num }) {
			return known.name
		}
		return devices.first { $0.id == deviceId }.map { $0.longName ?? $0.name }
	}

	/// Radio `deviceId` when it's one of the user's and is off: what its window shows (W-02). Not:
	/// - a radio the store no longer has (`knownRadios`), after Clear App Data or a restore
	///   (review V27-4);
	/// - one connected on another device id, such as over TCP instead of BLE (W-03, review V27-8);
	/// - one being removed (review V27-2), or released for a firmware update (review V27-6).
	func offlineRadio(_ deviceId: UUID) -> OfflineRadio? {
		guard !isRadioConnected(deviceId), !radiosReleasedForUpdate.contains(deviceId), let num = knownNodeNums[deviceId],
			  knownRadios.contains(where: { $0.nodeNum == num }), !isRadioConnected(nodeNum: num), !radiosBeingRemoved.contains(num) else {
			return nil
		}
		return OfflineRadio(deviceId: deviceId, nodeNum: num, name: radioName(of: deviceId) ?? num.toHex())
	}

	/// The user's radios that are off, by name, each with the device it was last connected on: the
	/// Mac lists them with the connected ones, to open, connect or remove (W-02).
	var offlineKnownRadios: [OfflineRadio] {
		knownRadios
			.compactMap { radio in deviceId(ofRadio: radio.nodeNum).flatMap(offlineRadio) }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	/// The device to connect radio `deviceId` with: discovery's, or a saved manual connection.
	/// Nil until discovery sees it.
	func connectableDevice(_ deviceId: UUID) -> Device? {
		devices.first { $0.id == deviceId } ?? ManualConnectionList.shared.connectionsList.first { $0.id == deviceId }
	}

	/// The peripheral id of `window`'s radio. For `.firstRadio`, `PreferredRadio.peripheralId`.
	func radioPeripheralId(for window: RadioWindow) -> String {
		window.deviceId?.uuidString ?? PreferredRadio.peripheralId
	}

	/// What `window`'s radio reported: its firmware edition, version and region presets. For
	/// `.firstRadio`, the manager's `firmwareEdition`, `connectedVersion` and `loRaRegionPresets`.
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
	/// the window. For `.firstRadio`, `firmwareUpdateRequired`.
	func firmwareUpdateRequired(for window: RadioWindow) -> Bool {
		guard window.deviceId != nil else { return firmwareUpdateRequired }
		return linkStatus(for: window).firmwareUpdateRequired
	}

	/// When `window`'s radio last finished sending its configuration. For `.firstRadio`,
	/// `lastConfigRefresh`.
	func lastConfigRefresh(for window: RadioWindow) -> Date? {
		guard window.deviceId != nil else { return lastConfigRefresh }
		return session(for: window)?.lastConfigRefresh
	}

	/// `window`'s radio's MQTT client proxy. For `.firstRadio`, `mqttProxyConnected` and `mqttTopics`.
	func mqttProxyConnected(for window: RadioWindow) -> Bool {
		session(for: window)?.mqtt?.isConnected ?? false
	}

	func mqttTopics(for window: RadioWindow) -> [String] {
		session(for: window)?.mqtt?.topics ?? []
	}

	/// `checkIsVersionSupported` for `window`'s radio: its own reported firmware
	/// (`isVersionSupported(forVersion:on:)`); for `.firstRadio`, exactly `checkIsVersionSupported`.
	func isVersionSupported(forVersion version: String, for window: RadioWindow) -> Bool {
		guard window.deviceId != nil else { return checkIsVersionSupported(forVersion: version) }
		guard let session = session(for: window) else {
			// Disconnected: the version it last reported, not another radio's (review V11).
			return Self.isFirmwareSupported(knownFirmwareVersions[radioNodeNum(for: window)], minimum: version)
		}
		return isVersionSupported(forVersion: version, on: session)
	}

	/// `window`'s radio's connection (`linkStatus(of:)`). For `.firstRadio` with no radio at all,
	/// the manager's own state.
	func linkStatus(for window: RadioWindow) -> RadioLinkStatus {
		if let deviceId = window.deviceId ?? firstDeviceId {
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
