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

	/// Sets why `session`'s radio needs the user, or clears it. For a radio that isn't focused,
	/// a new reason also prompts the user, naming the radio (`radioAttentionPrompt`).
	func setAttention(_ attention: RadioAttention?, for session: RadioSession) {
		guard session.attention != attention else { return }
		objectWillChange.send()
		session.attention = attention
		let name = session.device.longName ?? session.device.name
		if let attention {
			Logger.transport.info("⚠️ [Radios] \(name, privacy: .public): \(attention.shortCaption, privacy: .public)")
			if session !== activeConnection, session.device.id != oneWindowShownRadio {
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

	/// Why `session`'s radio needs the user from its lock-down state: locked, unlocking failed or
	/// rate limited, or it needs a passphrase. Nil when unlocked, or not lock-down firmware.
	func lockdownAttention(for session: RadioSession) -> RadioAttention? {
		Self.attention(for: session.lockdown.state)
	}

	/// The attention a lock-down state asks for.
	static func attention(for state: LockdownState) -> RadioAttention? {
		switch state {
		case .needsProvision: return .needsPassphrase
		case .locked(let reason): return reason == "auto_replay_wrong_passphrase" ? .unlockFailed : .locked
		case .unlockFailed, .unlockBackoff: return .unlockFailed
		case .none, .unlocked, .lockNowAcknowledged: return nil
		}
	}

	// MARK: - Lock-down (T065, T073, T188, T301)

	/// After `session`'s coordinator took a lock-down status. Every radio's own coordinator runs
	/// the same state machine, the focused radio's included: the saved passphrase is tried, and
	/// the sheet shows when the user is needed. Here, what follows for the app:
	/// - a radio that isn't focused and needs the user is asked about by name (`setAttention`),
	///   and its Unlock opens its own sheet (`radioUnlockRequest`);
	/// - unlocked: that's cleared; a radio already connected alongside gets its config again (a
	///   connect in progress carries on by itself);
	/// - Lock Now acknowledged by the radio's LOCKED status: its connection closes, so the next
	///   connect asks for the passphrase again.
	func lockdownStateChanged(_ session: RadioSession) {
		let state = session.lockdown.state
		let isFocused = session === activeConnection
		if !isFocused {
			if let attention = Self.attention(for: state) {
				setAttention(attention, for: session)
			} else if session.attention?.isLockdown == true {
				setAttention(nil, for: session)
			}
		}
		switch state {
		case .unlocked:
			if radioUnlockRequest?.id == session.device.id {
				radioUnlockRequest = nil
			}
			guard !isFocused, additionalRadio(for: session) != nil, connectAttempts[session.device.id]?.session !== session else { return }
			Task { @MainActor [weak self] in
				try? await self?.sendWantConfig(on: session)
			}
		case .lockNowAcknowledged:
			Task { @MainActor [weak self] in
				if isFocused {
					try? await self?.closeConnection()
				} else {
					try? await session.connection.disconnect(withError: nil, shouldReconnect: true)
				}
			}
		default:
			break
		}
	}
}
