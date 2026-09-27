//
//  AccessoryManager+RadioAttention.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import OSLog

// MARK: - A radio that needs the user (feature 021, T065, T073)

/// Why a connected radio needs the user: a lock-down passphrase, or a firmware update.
///
/// Every radio stays connected either way, like the focused radio always has (D-17). The focused
/// radio shows the passphrase sheet or the update screen; another radio gets a prompt naming it,
/// whose Unlock or Update focuses it (without reconnecting, T072), which shows those screens.
enum RadioAttention: Equatable {
	/// Lock-down firmware, locked, and no saved passphrase unlocked it.
	case locked
	/// Lock-down firmware that has never had a passphrase set.
	case needsPassphrase
	/// The saved or entered passphrase was refused.
	case unlockFailed
	/// Firmware below `AccessoryManager.minimumVersion`.
	case firmwareTooOld(version: String)

	var isLockdown: Bool {
		if case .firmwareTooOld = self { return false }
		return true
	}

	/// The prompt's title and the Connect tab row's caption.
	func title(radioName: String) -> String {
		switch self {
		case .locked, .unlockFailed:
			return String.localizedStringWithFormat("%@ is locked".localized, radioName)
		case .needsPassphrase:
			return String.localizedStringWithFormat("%@ needs a passphrase".localized, radioName)
		case .firmwareTooOld:
			return String.localizedStringWithFormat("%@ needs a firmware update".localized, radioName)
		}
	}

	var message: String {
		switch self {
		case .locked:
			return "Its lock-down passphrase is needed before its real settings and messages can be used.".localized
		case .unlockFailed:
			return "Its saved passphrase didn't unlock it. Enter the passphrase to unlock it.".localized
		case .needsPassphrase:
			return "Its lock-down firmware has no passphrase yet. Set one to use it.".localized
		case .firmwareTooOld(let version):
			return String.localizedStringWithFormat("It runs firmware %@, which is no longer supported. It stays connected so you can update it.".localized, version)
		}
	}

	/// What the prompt's button does: focus the radio, which shows its sheet or update screen.
	var actionTitle: String {
		switch self {
		case .locked, .unlockFailed, .needsPassphrase: return "Unlock".localized
		case .firmwareTooOld: return "Update".localized
		}
	}

	var shortCaption: String {
		switch self {
		case .locked, .unlockFailed: return "Locked".localized
		case .needsPassphrase: return "Needs a passphrase".localized
		case .firmwareTooOld: return "Needs a firmware update".localized
		}
	}
}

/// The prompt for a radio that isn't focused and needs the user (T073).
struct RadioAttentionPrompt: Identifiable, Equatable {
	/// The radio's device id.
	let id: UUID
	let radioName: String
	let attention: RadioAttention
}

extension AccessoryManager {

	/// Sets why `session`'s radio needs the user, or clears it. For a radio that isn't focused,
	/// a new reason also prompts the user, naming the radio (`radioAttentionPrompt`).
	func setAttention(_ attention: RadioAttention?, for session: RadioSession) {
		guard session.attention != attention else { return }
		objectWillChange.send()
		session.attention = attention
		let name = session.device.longName ?? session.device.name
		if let attention {
			Logger.transport.info("⚠️ [Radios] \(name, privacy: .public): \(attention.shortCaption, privacy: .public)")
			if session !== activeConnection {
				radioAttentionPrompt = RadioAttentionPrompt(id: session.device.id, radioName: name, attention: attention)
			}
		} else if radioAttentionPrompt?.id == session.device.id {
			radioAttentionPrompt = nil
		}
	}

	// MARK: - Firmware (T065, T073)

	/// True when `version` (from the radio's metadata) meets `minimumVersion`. Permissive without
	/// a version, like `checkIsVersionSupported` for the focused radio.
	static func isFirmwareSupported(_ version: String?, minimum: String) -> Bool {
		guard let version, !version.isEmpty else { return true }
		let comparison = minimum.compare(version, options: .numeric)
		return comparison == .orderedAscending || comparison == .orderedSame
	}

	/// `.firmwareTooOld` when the radio's firmware is below `minimumVersion`, else nil. Connect
	/// Step 6 sets it for a radio that isn't focused; the focused radio has the update gate.
	func firmwareAttention(for session: RadioSession) -> RadioAttention? {
		let version = session.device.firmwareVersion
		guard !Self.isFirmwareSupported(version, minimum: minimumVersion) else { return nil }
		return .firmwareTooOld(version: version ?? "?")
	}

	// MARK: - Lock-down on a radio that isn't focused (T065, T073)

	/// Lock-down status from a radio that isn't focused. The focused radio's goes to
	/// `LockdownCoordinator` and its passphrase sheet.
	/// - locked, with a passphrase saved for this radio (by an earlier unlock): the passphrase is
	///   sent once on this connection;
	/// - locked otherwise, needing a passphrase, or refusing one: the radio stays connected and
	///   needs the user (`setAttention`), who unlocks it by focusing it;
	/// - unlocked: that's cleared; a connect in progress carries on by itself (the config request
	///   finished before the status arrived, and Step 5 asks for the node DB again if the first
	///   request went unanswered), and a radio that was already connected gets its config again.
	func handleAdditionalLockdown(_ status: LockdownStatus, session: RadioSession, store: LockdownPassphraseStoring = LockdownPassphraseStore.shared) {
		let name = session.device.longName ?? session.device.name
		switch status.state {
		case .disabled, .unspecified, .UNRECOGNIZED:
			return

		case .unlocked:
			Logger.transport.info("🔒🔗➕ [Additional] \(name, privacy: .public) unlocked")
			if session.attention?.isLockdown == true {
				setAttention(nil, for: session)
			}
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
						self?.setAttention(.locked, for: session)
					}
				}
				return
			}
			Logger.transport.warning("🔒🔗➕ [Additional] \(name, privacy: .public) is locked and has no saved passphrase that works")
			setAttention(session.lockdownAutoAttempted ? .unlockFailed : .locked, for: session)

		case .needsProvision:
			setAttention(.needsPassphrase, for: session)

		case .unlockFailed:
			setAttention(.unlockFailed, for: session)
		}
	}
}
