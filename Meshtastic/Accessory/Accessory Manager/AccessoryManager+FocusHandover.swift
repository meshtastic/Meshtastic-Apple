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

	/// The connected radio that would take the focus now, or nil when nothing should: a radio is
	/// focused or connecting, a switch or firmware update is in progress, or the user
	/// disconnected on purpose.
	var focusHandoverCandidate: Device? {
		guard activeConnection == nil,
			  !isConnecting,
			  !isSwitchingDevices,
			  !otaInProgress,
			  !userRequestedConnectionCancellation else { return nil }
		return additionalRadioDevices.first { $0.connectionState == .connected }
	}

	/// Called when the focused radio's connection closes. With other radios connected, waits
	/// `focusHandoverDelay` for the focused radio's own reconnect, then gives the focus to one of
	/// them. The dropped radio is remembered, so it comes back as an additional radio.
	func scheduleFocusHandover(previousRadio: Int64?, after delay: Duration = focusHandoverDelay) {
		focusHandoverTask?.cancel()
		guard !additionalRadios.isEmpty else {
			focusHandoverTask = nil
			return
		}
		focusHandoverTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: delay)
			var waited = delay
			while !Task.isCancelled, let self {
				if self.activeConnection != nil || self.additionalRadios.isEmpty {
					return
				}
				if let next = self.focusHandoverCandidate {
					Logger.transport.info("🔀 The focused radio didn't come back; \(next.name, privacy: .public) takes the focus")
					if let previousRadio {
						await MeshPackets.shared.setRadioAutoConnect(nodeNum: previousRadio, true)
					}
					await switchToDevice(next, accessoryManager: self, appState: self.appState, keepPreviousRadio: false)
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
			  !isSwitchingDevices,
			  !otaInProgress,
			  !userRequestedConnectionCancellation,
			  UserDefaults.autoconnectOnDiscovery else { return nil }
		let preferredId = UserDefaults.preferredPeripheralId
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
			let preferredNum = Int64(UserDefaults.preferredPeripheralNum)
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
