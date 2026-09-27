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

	/// Throws when the radio's firmware is below `minimumVersion`. The focused radio stays
	/// connected on old firmware behind the update gate; another radio has no gate yet (T073), so
	/// its connect ends here (Step 6) and the user focuses it to update it.
	func checkAdditionalRadioFirmware(_ session: RadioSession) throws {
		let device = session.device
		guard !Self.isFirmwareSupported(device.firmwareVersion, minimum: minimumVersion) else { return }
		throw AdditionalRadioNeedsFocusError(
			radioName: device.longName ?? device.name,
			reason: .firmwareTooOld(version: device.firmwareVersion ?? "?")
		)
	}
}

// MARK: - Lock-down on additional radios (feature 021, T065)

extension AccessoryManager {

	/// Lock-down status from a radio that isn't focused. The focused radio keeps
	/// `LockdownCoordinator` and its passphrase sheet until each radio gets its own (T073), so:
	/// - locked, with a passphrase saved for this radio (by an earlier unlock while it was
	///   focused): the passphrase is sent once on this connection;
	/// - unlocked: a connect in progress carries on by itself (the config request finished
	///   before the status arrived, and Step 5 asks for the node DB again if the first request
	///   went unanswered); a radio that was already connected gets its config again;
	/// - locked with no usable passphrase, needing provisioning, or refusing the passphrase:
	///   its connect ends with `AdditionalRadioNeedsFocusError`, which isn't retried, or it's
	///   disconnected if it was already connected.
	func handleAdditionalLockdown(_ status: LockdownStatus, session: RadioSession, store: LockdownPassphraseStoring = LockdownPassphraseStore.shared) {
		let name = session.device.longName ?? session.device.name
		switch status.state {
		case .disabled, .unspecified, .UNRECOGNIZED:
			return

		case .unlocked:
			Logger.transport.info("🔒🔗➕ [Additional] \(name, privacy: .public) unlocked")
			guard additionalRadio(for: session) != nil, connectAttempts[session.device.id]?.session !== session else { return }
			Task { @MainActor [weak self] in
				try? await self?.sendWantConfig(on: session)
			}

		case .locked:
			if !session.lockdownAutoAttempted,
			   let myNum = session.nodeNum.map({ UInt32(truncatingIfNeeded: $0) }), myNum != 0,
			   let stored = store.get(peripheralID: session.device.id),
			   let passphrase = stored.passphrase.data(using: .utf8) {
				var auth = LockdownAuth()
				auth.passphrase = passphrase
				auth.bootsRemaining = stored.bootsRemaining
				auth.validUntilEpoch = stored.validUntilEpoch
				auth.maxSessionSeconds = stored.maxSessionSeconds
				guard let toRadio = Self.lockdownAuthPacket(to: myNum, auth: auth) else { return }
				session.lockdownAutoAttempted = true
				Logger.transport.info("🔒🔗➕ [Additional] \(name, privacy: .public) is locked; sending its saved passphrase")
				Task { @MainActor [weak self] in
					do {
						try await session.connection.send(toRadio)
					} catch {
						Logger.transport.error("🔒🔗➕ [Additional] Passphrase to \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
						await self?.stopLockedAdditionalRadio(session)
					}
				}
				return
			}
			Logger.transport.warning("🔒🔗➕ [Additional] \(name, privacy: .public) is locked and has no saved passphrase that works")
			Task { await stopLockedAdditionalRadio(session) }

		case .needsProvision, .unlockFailed:
			Logger.transport.warning("🔒🔗➕ [Additional] \(name, privacy: .public) lock-down: \(String(describing: status.state), privacy: .public)")
			Task { await stopLockedAdditionalRadio(session) }
		}
	}

	/// Ends the radio's connect with `AdditionalRadioNeedsFocusError`, which also disconnects it.
	/// A radio that was already connected is disconnected here, without a reconnect.
	private func stopLockedAdditionalRadio(_ session: RadioSession) async {
		guard additionalRadio(for: session) != nil else { return }
		let error = AdditionalRadioNeedsFocusError(radioName: session.device.longName ?? session.device.name, reason: .locked)
		if let attempt = connectAttempts[session.device.id], attempt.session === session, let stepper = attempt.stepper {
			await stepper.cancelCurrentlyExecutingStep(withError: error, cancelFullProcess: true)
			return
		}
		await disconnectAdditionalRadio(session.device.id)
	}
}
