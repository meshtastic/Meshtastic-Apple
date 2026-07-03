//
//  LockdownSheet.swift
//  Meshtastic
//
//  Full-screen sheet rendered when LockdownCoordinator.state requires user
//  action: NEEDS_PROVISION, LOCKED, UNLOCK_FAILED, or UNLOCK_BACKOFF.
//  Presented by ContentView via .fullScreenCover (T012); presentation logic
//  is intentionally not in this file.
//
//  See specs/007-lockdown-mode/spec.md US-1 / US-2 and contracts/coordinator-protocol.md.
//
import SwiftUI
import OSLog

struct LockdownSheet: View {

	@EnvironmentObject private var lockdown: LockdownCoordinator
	@EnvironmentObject private var accessoryManager: AccessoryManager

	var body: some View {
		NavigationStack {
			Group {
				switch lockdown.state {
				case .needsProvision:
					PassphraseEntryContent(mode: .provision)
				case .locked(let reason):
					PassphraseEntryContent(mode: .unlock(reason: reason))
				case .unlockFailed:
					PassphraseEntryContent(mode: .unlock(reason: "auto_replay_wrong_passphrase"),
										   inlineError: "lockdown.passphrase.wrong".localized)
				case .unlockBackoff(let deadline):
					BackoffCountdownContent(deadline: deadline)
				case .none, .unlocked, .lockNowAcknowledged:
					// Sheet should already be dismissed by ContentView's cover binding.
					EmptyView()
				}
			}
			.interactiveDismissDisabled(true)
		}
	}
}

// MARK: - Passphrase entry (provision + unlock)

private struct PassphraseEntryContent: View {

	enum Mode: Equatable {
		case provision
		case unlock(reason: String)
	}

	let mode: Mode
	var inlineError: String?

	@EnvironmentObject private var lockdown: LockdownCoordinator
	@EnvironmentObject private var accessoryManager: AccessoryManager

	@State private var passphrase: String = ""
	@State private var bootsString: String = ""
	@State private var hoursString: String = ""
	@State private var sessionMinutesString: String = ""
	@State private var showAdvanced: Bool = false
	@FocusState private var passphraseFocused: Bool

	private var passphraseByteCount: Int {
		passphrase.data(using: .utf8)?.count ?? .max
	}

	private var isPassphraseValid: Bool {
		(1...32).contains(passphraseByteCount)
	}

	/// Empty string is treated as 0 (firmware default). Non-empty must parse as UInt32.
	private var bootsParsed: UInt32? {
		bootsString.isEmpty ? 0 : UInt32(bootsString)
	}

	private var hoursParsed: UInt32? {
		hoursString.isEmpty ? 0 : UInt32(hoursString)
	}

	/// Per-boot session uptime cap in minutes. Empty / 0 = unlimited (firmware
	/// default). Converted to seconds for `LockdownAuth.max_session_seconds`.
	private var sessionMinutesParsed: UInt32? {
		sessionMinutesString.isEmpty ? 0 : UInt32(sessionMinutesString)
	}

	private var areTTLFieldsValid: Bool {
		bootsParsed != nil && hoursParsed != nil && sessionMinutesParsed != nil
	}

	private var coordinatorReady: Bool {
		accessoryManager.activeConnection?.device.num != nil
	}

	private var isSubmitEnabled: Bool {
		isPassphraseValid && areTTLFieldsValid && coordinatorReady
	}

	private var titleKey: LocalizedStringKey {
		switch mode {
		case .provision: return "lockdown.set_passphrase.title"
		case .unlock: return "lockdown.unlock.title"
		}
	}

	private var submitKey: LocalizedStringKey {
		switch mode {
		case .provision: return "lockdown.set_passphrase.submit"
		case .unlock: return "lockdown.unlock.submit"
		}
	}

	private var hintKey: LocalizedStringKey {
		switch mode {
		case .provision:
			return "lockdown.set_passphrase.hint"
		case .unlock(let reason):
			switch reason {
			case "needs_auth":
				return "lockdown.locked.needs_auth"
			case "token_missing", "token_expired", "token_boots_zero":
				return "lockdown.locked.token_expired"
			case "token_rtc_unavailable":
				return "lockdown.locked.token_rtc"
			case "token_hmac_fail", "token_dek_fail", "token_wrong_size", "token_bad_magic":
				return "lockdown.locked.token_tamper"
			case "auto_replay_wrong_passphrase":
				return "lockdown.locked.auto_replay_failed"
			default:
				return "lockdown.locked.needs_auth"
			}
		}
	}

	var body: some View {
		Form {
			Section {
				Text(hintKey)
					.font(.footnote)
					.foregroundStyle(.secondary)
				SecureField("lockdown.passphrase.field", text: $passphrase)
					.textContentType(.password)
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
					.focused($passphraseFocused)
				if let inlineError {
					Label(inlineError, systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.red)
						.font(.footnote)
				}
			} footer: {
				HStack {
					Spacer()
					Text("\(passphraseByteCount)/32")
						.font(.caption)
						.monospacedDigit()
						.foregroundStyle(isPassphraseValid ? Color.secondary : Color.red)
						.accessibilityLabel(Text("Passphrase length \(passphraseByteCount) of 32 bytes"))
				}
			}

			Section {
				DisclosureGroup(isExpanded: $showAdvanced) {
					VStack(alignment: .leading, spacing: 4) {
						Text("lockdown.session.boots_remaining")
							.font(.footnote)
						TextField("0", text: $bootsString)
							.keyboardType(.numberPad)
						Text("lockdown.session.boots_caption")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					VStack(alignment: .leading, spacing: 4) {
						Text("lockdown.session.hours_valid")
							.font(.footnote)
						TextField("0", text: $hoursString)
							.keyboardType(.numberPad)
						Text("lockdown.session.hours_caption")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					VStack(alignment: .leading, spacing: 4) {
						Text("lockdown.session.cap_minutes")
							.font(.footnote)
						TextField("0", text: $sessionMinutesString)
							.keyboardType(.numberPad)
						Text("lockdown.session.cap_caption")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				} label: {
					Label("lockdown.session.section", systemImage: "clock.badge")
				}
			}

			Section {
				Button(action: submit) {
					HStack {
						Spacer()
						Text(submitKey)
							.bold()
						Spacer()
					}
				}
				.disabled(!isSubmitEnabled)
				.accessibilityHint(Text(isSubmitEnabled ? "" : "Enter a passphrase between 1 and 32 bytes."))
				if !coordinatorReady {
					Text("lockdown.connecting")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.navigationTitle(titleKey)
		.navigationBarTitleDisplayMode(.inline)
		.dynamicTypeSize(...DynamicTypeSize.accessibility3)
		.onAppear { passphraseFocused = true }
		.onDisappear { passphrase = "" }
	}

	private func submit() {
		guard isSubmitEnabled else { return }
		let boots = bootsParsed ?? 0
		// Clamp instead of trapping: UInt32 arithmetic overflows (and crashes) for
		// large user-typed Hours/Minutes values, e.g. 2000000 hours * 3600.
		let validUntilEpoch: UInt32 = {
			guard let hours = hoursParsed, hours > 0 else { return 0 }
			let epoch = UInt64(Date().timeIntervalSince1970) + UInt64(hours) * 3600
			return UInt32(clamping: epoch)
		}()
		let maxSessionSeconds: UInt32 = {
			guard let minutes = sessionMinutesParsed, minutes > 0 else { return 0 }
			return UInt32(clamping: UInt64(minutes) * 60)
		}()
		lockdown.submitPassphrase(passphrase,
								  bootsRemaining: boots,
								  validUntilEpoch: validUntilEpoch,
								  maxSessionSeconds: maxSessionSeconds)
		// Wipe local copy immediately; coordinator also clears its own pending copy
		// on response. NFR-002.
		passphrase = ""
	}
}

// MARK: - Backoff countdown

private struct BackoffCountdownContent: View {

	let deadline: Date

	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "lock.trianglebadge.exclamationmark")
				.resizable()
				.scaledToFit()
				.frame(width: 64, height: 64)
				.foregroundStyle(.orange)
			Text("lockdown.backoff.title")
				.font(.title2)
				.bold()
			TimelineView(.periodic(from: .now, by: 1)) { context in
				let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
				Text("lockdown.backoff.body \(remaining)")
					.font(.headline)
					.monospacedDigit()
					.accessibilityLabel(Text("lockdown.backoff.body \(remaining)"))
			}
			Text("lockdown.backoff.explanation")
				.font(.footnote)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.padding(.horizontal)
		}
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.navigationTitle("lockdown.backoff.title")
		.navigationBarTitleDisplayMode(.inline)
	}
}
