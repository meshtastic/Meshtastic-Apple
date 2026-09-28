//
//  AccessoryManager+FocusHandover.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog

// MARK: - Focus handover (feature 021)

extension AccessoryManager {

	/// How long a focused radio that dropped gets to come back before another connected radio
	/// takes the focus.
	static let focusHandoverDelay: Duration = .seconds(30)
	/// How often the handover checks again while something else is in progress.
	static let focusHandoverRecheck: Duration = .seconds(10)
	/// When it stops waiting.
	static let focusHandoverGiveUp: Duration = .seconds(300)

	/// A focused connect is running or waiting for the handshake gate. `isConnecting` only says so
	/// once it has passed the gate (T152).
	var hasFocusedConnectInProgress: Bool {
		connectAttempts.values.contains { $0.isFocused && !$0.isCancelled }
	}

	/// The connected radio that would take the focus now, or nil when nothing should: a radio is
	/// focused or connecting, a switch or firmware update is in progress, or the user
	/// disconnected on purpose.
	var focusHandoverCandidate: Device? {
		guard activeConnection == nil,
			  !isConnecting,
			  !hasFocusedConnectInProgress,
			  !isSwitchingDevices,
			  !otaInProgress,
			  // A discovery scan's radio reboots into each preset; it comes back as the focus.
			  discoveryScanEngine?.isScanning != true,
			  !userRequestedConnectionCancellation else { return nil }
		let connected = additionalRadioDevices.filter { $0.connectionState == .connected }
		// A radio that needs the user (locked, old firmware) would put its passphrase sheet or
		// update screen over the app; one that doesn't goes first (T182).
		return connected.first { additionalRadios[$0.id]?.attention == nil } ?? connected.first
	}

	/// Called when the focused radio's connection closes. With other radios connected, waits
	/// `focusHandoverDelay` for the focused radio's own reconnect, then gives the focus to one of
	/// them. The dropped radio (`previousDevice`) is then tried again as an additional radio until
	/// it's back (T149): discovery only brings back the preferred radio, which is now the new one.
	func scheduleFocusHandover(previousRadio: Int64?, previousDevice: Device? = nil, after delay: Duration = focusHandoverDelay) {
		// A close with nothing open (the dropped radio's own reconnect failing) while a handover
		// is pending is still about the radio that dropped (T171).
		var previousRadio = previousRadio
		var previousDevice = previousDevice
		if previousRadio == nil, previousDevice == nil, focusHandoverTask != nil, let pending = handoverPrevious {
			previousRadio = pending.radioNum
			previousDevice = pending.device
		}
		focusHandoverTask?.cancel()
		guard !additionalRadios.isEmpty else {
			focusHandoverTask = nil
			handoverPrevious = nil
			return
		}
		handoverPrevious = (previousRadio, previousDevice)
		focusHandoverTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: delay)
			var waited = delay
			defer {
				if !Task.isCancelled {
					self?.focusHandoverTask = nil
					self?.handoverPrevious = nil
				}
			}
			while !Task.isCancelled, let self {
				if self.activeConnection != nil || self.additionalRadios.isEmpty {
					return
				}
				if let next = self.focusHandoverCandidate {
					Logger.transport.info("🔀 The focused radio didn't come back; \(next.name, privacy: .public) takes the focus")
					// Read now, not when scheduled: a radio removed meanwhile is no longer here
					// (`stopBringingBack`, T202).
					let previousRadio = self.handoverPrevious?.radioNum
					let previousDevice = self.handoverPrevious?.device
					if let previousRadio {
						await MeshPackets.shared.setRadioAutoConnect(nodeNum: previousRadio, true)
					}
					await switchToDevice(next, accessoryManager: self, appState: self.appState, keepPreviousRadio: false)
					if let previousDevice, self.activeConnection != nil, !self.isRadioConnected(previousDevice.id) {
						self.scheduleAdditionalRadioReconnect(previousDevice)
					}
					return
				}
				guard waited < Self.focusHandoverGiveUp else { return }
				try? await Task.sleep(for: Self.focusHandoverRecheck)
				waited += Self.focusHandoverRecheck
			}
		}
	}

	// MARK: - Remembered radio when the preferred one is missing

	/// How long discovery looks for the preferred radio before a remembered one is connected.
	static let rememberedRadioFallbackDelay: Duration = .seconds(30)

	/// Of the remembered radios, the first one discovery can see right now, when a fallback
	/// should happen at all: nothing connected or connecting, auto-connect on, and the user
	/// didn't disconnect on purpose.
	func rememberedRadioFallbackCandidate(from remembered: [MeshPackets.RememberedRadio]) -> Device? {
		guard activeConnection == nil,
			  additionalRadios.isEmpty,
			  !isConnecting,
			  !hasFocusedConnectInProgress,
			  !isSwitchingDevices,
			  !otaInProgress,
			  !userRequestedConnectionCancellation,
			  UserDefaults.autoconnectOnDiscovery else { return nil }
		let preferredId = PreferredRadio.connectFirstPeripheralId
		for radio in remembered where radio.peripheralId != preferredId {
			if let seen = devices.first(where: { $0.id.uuidString == radio.peripheralId }) {
				return seen
			}
		}
		return nil
	}

	/// Started when discovery begins with nothing connected. If the preferred radio doesn't
	/// connect within `rememberedRadioFallbackDelay`, a remembered radio that's in range becomes
	/// the focused one, and the preferred radio is remembered so it joins when it shows up.
	func scheduleRememberedRadioFallback(after delay: Duration = rememberedRadioFallbackDelay) {
		rememberedRadioFallbackTask?.cancel()
		rememberedRadioFallbackTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: delay)
			guard let self, !Task.isCancelled else { return }
			let remembered = await MeshPackets.shared.rememberedRadios(excluding: [])
			guard let device = self.rememberedRadioFallbackCandidate(from: remembered) else { return }
			Logger.transport.info("🔁 [Remembered] The preferred radio didn't show up; connecting \(device.name, privacy: .public)")
			let preferredNum = PreferredRadio.nodeNum
			if preferredNum > 0 {
				await MeshPackets.shared.setRadioAutoConnect(nodeNum: preferredNum, true)
			}
			do {
				try await self.connect(to: device)
			} catch {
				Logger.transport.error("🔁 [Remembered] Connecting \(device.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}
}
