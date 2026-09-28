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

/// A locked radio that isn't focused, whose passphrase the user is entering (T188).
struct RadioUnlockRequest: Identifiable, Equatable {
	/// The radio's device id.
	let id: UUID
	let radioName: String
}

/// The prompt for a radio that isn't focused and needs the user (T073).
struct RadioAttentionPrompt: Identifiable, Equatable {
	/// The radio's device id.
	let id: UUID
	let radioName: String
	let attention: RadioAttention
}

extension AccessoryManager {

	/// Unlock or Update on a radio that isn't focused: focuses it without reconnecting, which
	/// shows its passphrase sheet or update screen. A locked radio reports its status in the
	/// middle of its connect, and a radio can't take the focus until its connect finishes, so
	/// then it takes the focus as soon as it does (T148). Reconnecting it as the focused radio
	/// instead would disconnect the focused one.
	///
	/// The same wait covers the other things that hold off a focus change: the focused radio's
	/// own connect and a firmware update (T179). The radio takes the focus when whichever it was
	/// ends (`retryPendingAttentionFocusSoon`).
	///
	/// A locked radio doesn't take the focus for its passphrase any more: it gets its own
	/// passphrase sheet, sent on its own connection (T188). Its connect may never finish while
	/// it's locked (if lock-down firmware doesn't answer the node-DB request then), and only a
	/// finished connect can take the focus. Update still focuses the radio for the update screen.
	func focusRadioNeedingAttention(_ deviceId: UUID) async {
		if let session = additionalRadios[deviceId], session.attention?.isLockdown == true {
			radioUnlockRequest = RadioUnlockRequest(id: deviceId, radioName: session.device.longName ?? session.device.name)
			return
		}
		if await focusConnectedRadio(deviceId) { return }
		guard additionalRadios[deviceId] != nil else { return }
		pendingAttentionFocus = deviceId
		Logger.transport.info("🔀 [Radios] Will focus \(self.additionalRadios[deviceId]?.device.name ?? "?", privacy: .public) once connects and updates in progress finish")
	}

	/// The radio the user chose Unlock or Update for takes the focus, if nothing holds it off any
	/// more; otherwise it keeps waiting. Called when a connect finishes and when an update ends.
	func focusPendingAttentionRadio(_ deviceId: UUID) async {
		guard pendingAttentionFocus == deviceId else { return }
		guard additionalRadios[deviceId] != nil else {
			pendingAttentionFocus = nil
			return
		}
		guard canFocusWithoutReconnecting(deviceId) else { return }
		pendingAttentionFocus = nil
		if !(await focusConnectedRadio(deviceId)) {
			Logger.transport.info("🔀 [Radios] Couldn't focus \(deviceId, privacy: .public)")
		}
	}

	/// Tries the waiting Unlock or Update again once the current work is done: after the caller
	/// returns, so a connect's attempt is gone by then.
	func retryPendingAttentionFocusSoon() {
		guard let deviceId = pendingAttentionFocus else { return }
		Task { @MainActor [weak self] in
			await self?.focusPendingAttentionRadio(deviceId)
		}
	}

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
				let prompt = RadioAttentionPrompt(id: session.device.id, radioName: name, attention: attention)
				pendingAttentionPrompts.removeAll { $0.id == prompt.id }
				if let shown = radioAttentionPrompt, shown.id != prompt.id {
					// Another radio's prompt is up; this one waits its turn rather than replacing it.
					pendingAttentionPrompts.append(prompt)
				} else {
					radioAttentionPrompt = prompt
				}
			}
		} else {
			pendingAttentionPrompts.removeAll { $0.id == session.device.id }
			if radioAttentionPrompt?.id == session.device.id {
				radioAttentionPrompt = nil
			}
		}
	}

	/// After a prompt closes: the next waiting radio that still needs the user and isn't focused.
	/// A moment later, so the closing alert is gone before the next one is presented.
	func showNextAttentionPrompt() {
		while let next = pendingAttentionPrompts.first {
			pendingAttentionPrompts.removeFirst()
			guard additionalRadios[next.id]?.attention == next.attention else { continue }
			Task { @MainActor [weak self] in
				try? await Task.sleep(for: .milliseconds(600))
				guard let self, self.additionalRadios[next.id]?.attention == next.attention else { return }
				if self.radioAttentionPrompt == nil {
					self.radioAttentionPrompt = next
				} else if self.radioAttentionPrompt?.id != next.id {
					self.pendingAttentionPrompts.insert(next, at: 0)
				}
			}
			return
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

	/// Why a radio that just lost the focus still needs the user: its firmware is too old, or
	/// its last lock-down status says it's locked. The focused radio's screens covered this; as
	/// an additional radio it gets its prompt and its row's caption back (T153).
	func attentionAfterLosingFocus(_ session: RadioSession) -> RadioAttention? {
		if let firmware = firmwareAttention(for: session) {
			return firmware
		}
		switch session.lastLockdownStatus?.state {
		case .locked: return session.lockdownAutoAttempted ? .unlockFailed : .locked
		case .needsProvision: return .needsPassphrase
		case .unlockFailed: return .unlockFailed
		default: return nil
		}
	}

	// MARK: - Lock-down on a radio that isn't focused (T065, T073, T188)

	/// Sends a passphrase the user entered for radio `deviceId`, which isn't focused, on its own
	/// connection, in the same packet as the focused radio's (`lockdownAuthPacket`). It's saved for
	/// the radio when the radio reports unlocked (`handleAdditionalLockdown`). False when it can't
	/// be sent: the radio is gone, hasn't reported its node number yet, or the passphrase isn't
	/// 1 to 32 bytes.
	@discardableResult
	func submitPassphrase(_ passphrase: String, bootsRemaining: UInt32, validUntilEpoch: UInt32, maxSessionSeconds: UInt32, toRadio deviceId: UUID) async -> Bool {
		guard let session = additionalRadios[deviceId],
			  let myNum = session.nodeNum.map({ UInt32(truncatingIfNeeded: $0) }), myNum != 0,
			  let data = passphrase.data(using: .utf8), (1...32).contains(data.count) else { return false }
		var auth = LockdownAuth()
		auth.passphrase = data
		auth.bootsRemaining = bootsRemaining
		auth.validUntilEpoch = validUntilEpoch
		auth.maxSessionSeconds = maxSessionSeconds
		guard let toRadio = Self.lockdownAuthPacket(to: myNum, auth: auth) else { return false }
		session.pendingPassphrase = StoredPassphrase(passphrase: passphrase, bootsRemaining: bootsRemaining, validUntilEpoch: validUntilEpoch, maxSessionSeconds: maxSessionSeconds)
		let name = session.device.longName ?? session.device.name
		Logger.transport.info("🔒🔗➕ [Additional] Sending the entered passphrase to \(name, privacy: .public)")
		do {
			try await session.connection.send(toRadio)
			return true
		} catch {
			session.pendingPassphrase = nil
			Logger.transport.error("🔒🔗➕ [Additional] Passphrase to \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	/// Lock-down status from a radio that isn't focused. The focused radio's goes to
	/// `LockdownCoordinator` and its passphrase sheet.
	/// - locked, with a passphrase saved for this radio (by an earlier unlock): the passphrase is
	///   sent once on this connection;
	/// - locked otherwise, needing a passphrase, or refusing one: the radio stays connected and
	///   needs the user (`setAttention`), who enters its passphrase in its own sheet
	///   (`submitPassphrase(_:…toRadio:)`, T188);
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
			session.unlockBackoffUntil = nil
			// A passphrase the user entered for it is kept for next time, as the focused radio's is.
			if let entered = session.pendingPassphrase {
				session.pendingPassphrase = nil
				if !store.save(peripheralID: session.device.id, entered) {
					Logger.transport.warning("🔒🔗➕ [Additional] Couldn't save the passphrase for \(name, privacy: .public)")
				}
			}
			if radioUnlockRequest?.id == session.device.id {
				radioUnlockRequest = nil
			}
			if session.attention?.isLockdown == true {
				setAttention(nil, for: session)
			}
			guard additionalRadio(for: session) != nil, connectAttempts[session.device.id]?.session !== session else { return }
			Task { @MainActor [weak self] in
				try? await self?.sendWantConfig(on: session)
			}

		case .locked:
			session.pendingPassphrase = nil
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
			// A saved passphrase that's refused outright is wrong now; the focused radio's
			// coordinator drops it the same way. One the user just typed was never saved.
			let enteredByUser = session.pendingPassphrase != nil
			session.pendingPassphrase = nil
			// Rate limited: its sheet counts down instead of taking another try (T196).
			session.unlockBackoffUntil = status.backoffSeconds > 0 ? Date(timeIntervalSinceNow: TimeInterval(status.backoffSeconds)) : nil
			if !enteredByUser, session.lockdownAutoAttempted, status.backoffSeconds == 0 {
				_ = store.delete(peripheralID: session.device.id)
			}
			setAttention(.unlockFailed, for: session)
		}
	}
}
