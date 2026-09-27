//
//  AccessoryManager+Focus.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import OSLog

// MARK: - Changing focus without reconnecting (feature 021, T072)

extension AccessoryManager {

	/// True when `deviceId` can take the focus without reconnecting: it's connected alongside
	/// the focused radio with its connect finished, and nothing is connecting, switching or
	/// updating firmware.
	func canFocusWithoutReconnecting(_ deviceId: UUID) -> Bool {
		guard let session = additionalRadios[deviceId],
			  session.device.connectionState == .connected,
			  connectAttempts[deviceId] == nil,
			  !otaInProgress else { return false }
		if let focused = activeConnection, connectAttempts[focused.device.id] != nil {
			return false
		}
		return true
	}

	/// Makes the connected radio `deviceId` the focused one without disconnecting anything
	/// (D-17: every radio runs the same steps and handlers, so focus is only which session
	/// `activeConnection` points at). The previous focused radio, if any, stays connected
	/// alongside it. Returns false, changing nothing, when `canFocusWithoutReconnecting` says no.
	///
	/// `previousStays: false` is for a previous radio that's disconnected straight after (Disconnect
	/// on the focused radio, a reset or removal): it gets no prompt or reminder first (T181).
	@discardableResult
	func focusConnectedRadio(_ deviceId: UUID, previousStays: Bool = true) async -> Bool {
		guard canFocusWithoutReconnecting(deviceId), let session = additionalRadios[deviceId] else { return false }
		let previous = activeConnection
		Logger.transport.info("🔀 Focusing \(session.device.name, privacy: .public) without reconnecting; \(previous?.device.name ?? "nothing", privacy: .public) stays connected")

		// The roles swap in one step, with no suspension in between, so no event from either
		// radio is handled while neither owns it.
		focusHandoverTask?.cancel()
		focusHandoverTask = nil
		// Its lock-down sheet or update screen takes over from the prompt (T073).
		setAttention(nil, for: session)
		additionalRadios.removeValue(forKey: deviceId)
		if let previous {
			additionalRadios[previous.device.id] = previous
		}
		activeConnection = session
		activeDeviceNum = session.nodeNum
		objectWillChange.send()

		applyFocusedRadioState(session)
		if previousStays, let previous, let attention = attentionAfterLosingFocus(previous) {
			setAttention(attention, for: previous)
		}
		if previousStays, let previous, let previousNum = previous.nodeNum {
			// Remembered, so it comes back alongside the focused radio next time.
			await MeshPackets.shared.noteRadioConnected(nodeNum: previousNum, transport: previous.device.transportType, autoConnect: true)
		}
		if let nodeNum = session.nodeNum {
			await MeshPackets.shared.noteRadioConnected(nodeNum: nodeNum, transport: session.device.transportType, autoConnect: nil)
		}
		return true
	}

	/// The app-wide state the focused radio's connect sets (plan.md › T070's table), for a radio
	/// that was already connected when it took the focus.
	private func applyFocusedRadioState(_ session: RadioSession) {
		PreferredRadio.peripheralId = session.device.id.uuidString
		if let nodeNum = session.nodeNum {
			PreferredRadio.nodeNum = nodeNum
		}
		firmwareUpdateRequired = !checkIsVersionSupported(forVersion: minimumVersion)
		allowDisconnect = true
		lastConnectionError = nil
		userRequestedConnectionCancellation = false
		updateState(.subscribed)

		Logger.datadog.setRadioContext(.firmwareVersion, session.device.firmwareVersion)
		Logger.datadog.setRadioContext(.hardwareModel, session.device.hardwareModel)

		// The passphrase sheet and Settings' lock-down section follow the focused radio.
		lockdownCoordinator?.onConnect(peripheralID: session.device.id)
		if let status = session.lastLockdownStatus {
			lockdownCoordinator?.handle(status)
		}

		if let nodeNum = session.nodeNum {
			MeshShareSnapshotBuilder.refresh(nodeNum: nodeNum, context: context)
		}
		initializeUnreadBadges()
		// The loop that shares the phone's position with every radio stops when a focused radio
		// drops; a radio taking the focus after that starts it again (T149).
		initializeLocationProvider()
		applyEventFirmwareNotificationDefaults(FirmwareEdition(rawValue: session.firmwareEdition.rawValue) ?? .vanilla)
		initializeTAKBridge()
		WatchSessionManager.shared.sendNodesToWatch()

		// Settings screens describe the focused radio; leave them now that it changed.
		appState?.router.popToRoot(tab: .settings)
	}
}
