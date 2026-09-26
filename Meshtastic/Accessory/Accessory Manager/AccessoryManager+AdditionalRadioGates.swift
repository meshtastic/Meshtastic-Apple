//
//  AccessoryManager+AdditionalRadioGates.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import OSLog

/// An additional radio can't run alongside the focused one until the user deals with it as the
/// focused radio, where the passphrase sheet and the firmware update gate live. Connects that
/// fail with it aren't retried.
struct AdditionalRadioNeedsFocusError: LocalizedError, Equatable {
	enum Reason: Equatable {
		/// Lock-down firmware, and no saved passphrase unlocks it.
		case locked
		/// Firmware below `AccessoryManager.minimumVersion`.
		case firmwareTooOld(version: String)
	}

	let radioName: String
	let reason: Reason

	var errorDescription: String? {
		switch reason {
		case .locked:
			return String.localizedStringWithFormat("%@ is locked. Focus it to enter its passphrase.".localized, radioName)
		case .firmwareTooOld(let version):
			return String.localizedStringWithFormat("%1$@ runs firmware %2$@, which is no longer supported. Focus it to update it.".localized, radioName, version)
		}
	}
}

// MARK: - Firmware gate on additional radios (feature 021, T065)

extension AccessoryManager {

	/// True when `version` (from the radio's metadata) meets `minimumVersion`. Permissive without
	/// a version, like `checkIsVersionSupported` for the focused radio.
	static func isFirmwareSupported(_ version: String?, minimum: String) -> Bool {
		guard let version, !version.isEmpty else { return true }
		let comparison = minimum.compare(version, options: .numeric)
		return comparison == .orderedAscending || comparison == .orderedSame
	}

	/// Throws when the additional radio's firmware is below `minimumVersion`. The focused radio
	/// stays connected on old firmware behind the update gate; an additional radio has no gate,
	/// so it's turned away and the user focuses it to update it.
	func checkAdditionalRadioFirmware(_ radio: AdditionalRadio) throws {
		let device = radio.session.device
		guard !Self.isFirmwareSupported(device.firmwareVersion, minimum: minimumVersion) else { return }
		throw AdditionalRadioNeedsFocusError(
			radioName: device.longName ?? device.name,
			reason: .firmwareTooOld(version: device.firmwareVersion ?? "?")
		)
	}
}

// MARK: - Lock-down on additional radios (feature 021, T065)

extension AccessoryManager {

	/// Lock-down status from an additional radio. The focused radio keeps `LockdownCoordinator`
	/// and its passphrase sheet; an additional radio has no prompt of its own, so:
	/// - locked, with a passphrase saved for this radio (by an earlier unlock while it was
	///   focused): the passphrase is sent once on this connection;
	/// - unlocked: a waiting handshake's request is sent again, or else the config is fetched
	///   again, the way the coordinator's unlock does for the focused radio;
	/// - locked with no usable passphrase, needing provisioning, or refusing the passphrase:
	///   the connect fails with `AdditionalRadioNeedsFocusError` and it isn't retried.
	func handleAdditionalLockdown(_ status: LockdownStatus, radio: AdditionalRadio, store: LockdownPassphraseStoring = LockdownPassphraseStore.shared) {
		let session = radio.session
		let name = session.device.longName ?? session.device.name
		switch status.state {
		case .disabled, .unspecified, .UNRECOGNIZED:
			return

		case .unlocked:
			Logger.transport.info("🔒🔗➕ [Additional] \(name, privacy: .public) unlocked")
			// A handshake still waiting gets its request again (the same nonce, so the waiting
			// connect completes on it); otherwise the config is refreshed.
			let waiting = Array(radio.pendingNonces.keys)
			Task { @MainActor [weak self] in
				guard let self, self.additionalRadios[radio.id] === radio else { return }
				guard !waiting.isEmpty else {
					try? await self.requestHandshake(radio, nonce: UInt32(NONCE_ONLY_CONFIG), timeout: .seconds(30))
					return
				}
				for nonce in waiting {
					var toRadio = ToRadio()
					toRadio.wantConfigID = nonce
					try? await session.connection.send(toRadio)
				}
			}

		case .locked:
			if !radio.lockdownAutoAttempted,
			   let myNum = session.nodeNum.map({ UInt32(truncatingIfNeeded: $0) }), myNum != 0,
			   let stored = store.get(peripheralID: radio.id),
			   let passphrase = stored.passphrase.data(using: .utf8) {
				var auth = LockdownAuth()
				auth.passphrase = passphrase
				auth.bootsRemaining = stored.bootsRemaining
				auth.validUntilEpoch = stored.validUntilEpoch
				auth.maxSessionSeconds = stored.maxSessionSeconds
				guard let toRadio = Self.lockdownAuthPacket(to: myNum, auth: auth) else { return }
				radio.lockdownAutoAttempted = true
				Logger.transport.info("🔒🔗➕ [Additional] \(name, privacy: .public) is locked; sending its saved passphrase")
				Task { @MainActor [weak self] in
					do {
						try await session.connection.send(toRadio)
					} catch {
						Logger.transport.error("🔒🔗➕ [Additional] Passphrase to \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
						await self?.stopLockedAdditionalRadio(radio)
					}
				}
				return
			}
			Logger.transport.warning("🔒🔗➕ [Additional] \(name, privacy: .public) is locked and has no saved passphrase that works")
			Task { await stopLockedAdditionalRadio(radio) }

		case .needsProvision, .unlockFailed:
			Logger.transport.warning("🔒🔗➕ [Additional] \(name, privacy: .public) lock-down: \(String(describing: status.state), privacy: .public)")
			Task { await stopLockedAdditionalRadio(radio) }
		}
	}

	/// Fails the radio's waiting handshakes with `AdditionalRadioNeedsFocusError`, which ends its
	/// connect (and disconnects it). With nothing waiting, it's disconnected here, without a
	/// reconnect.
	private func stopLockedAdditionalRadio(_ radio: AdditionalRadio) async {
		guard additionalRadios[radio.id] === radio else { return }
		let error = AdditionalRadioNeedsFocusError(radioName: radio.session.device.longName ?? radio.session.device.name, reason: .locked)
		let waiting = Array(radio.pendingNonces.keys)
		guard !waiting.isEmpty else {
			await disconnectAdditionalRadio(radio.id)
			return
		}
		for nonce in waiting {
			finishHandshake(radio, nonce: nonce, error: error)
		}
	}
}
