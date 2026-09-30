//
//  AccessoryManager+LaunchFallback.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog

// MARK: - Connecting at launch (feature 021)

extension AccessoryManager {

	/// The first radio's connect is running or waiting for the handshake gate. `isConnecting` only says so
	/// once it has passed the gate (T152).
	var hasFirstConnectInProgress: Bool {
		connectAttempts.values.contains { $0.isFirst && !$0.isCancelled }
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
			  !hasFirstConnectInProgress,
			  !isSwitchingDevices,
			  !otaInProgress,
			  !userRequestedConnectionCancellation,
			  UserDefaults.autoconnectOnDiscovery else { return nil }
		let preferredId = PreferredRadio.peripheralId
		for radio in remembered where radio.peripheralId != preferredId {
			if let seen = devices.first(where: { $0.id.uuidString == radio.peripheralId }) {
				return seen
			}
		}
		return nil
	}

	/// Started when discovery begins with nothing connected. If the preferred radio doesn't
	/// connect within `rememberedRadioFallbackDelay`, a remembered radio that's in range becomes
	/// the first one, and the preferred radio is remembered so it joins when it shows up.
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
