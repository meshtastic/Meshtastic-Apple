//
//  Security.swift
//  Meshtastic
//
// Copyright(c) Garth Vander Houwen 8/7/24.
//

import Foundation
import SwiftUI
import SwiftData
import MeshtasticProtobufs

struct SecurityConfig: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var lockdown: LockdownCoordinator
	@Environment(\.dismiss) private var goBack

	@State private var showLockNowAlert: Bool = false

	let node: NodeInfoEntity?

	@State var hasChanges = false
	@State private var publicKey = ""
	// Security config saves contain the complete keypair. Keep the device-provided
	// private key unchanged when writing other settings; it is presented read-only below.
	@State private var preservedPrivateKey = Data()
	@State private var adminKey: String = ""
	@State private var adminKey2: String = ""
	@State private var adminKey3: String = ""
	@State private var hasValidAdminKey: Bool = true
	@State private var hasValidAdminKey2: Bool = true
	@State private var hasValidAdminKey3: Bool = true
	@State private var isManaged = false
	@State private var serialEnabled = false
	@State private var debugLogApiEnabled = false
	@State var packetAuthenticitySelection = PacketAuthenticitySelectionState()
	@State private var backupStatus: KeyBackupStatus?
	@State private var saveError: String?
	@State private var isPrivateKeyRevealed = false

	private var hasValidDeviceIdentity: Bool {
		guard let storedPublicKey = node?.securityConfig?.publicKey else {
			return false
		}
		return IdentityKeyPairBackup.isValid(
			privateKey: preservedPrivateKey,
			publicKey: storedPublicKey
		)
	}

	private var privateKey: String {
		preservedPrivateKey.base64EncodedString()
	}

	var body: some View {
		Form {
			ConfigHeader(title: "Security", config: \.securityConfig, node: node, onAppear: setSecurityValues)
			deviceIdentitySection
			identityBackupSection
			packetAuthenticitySection
			adminAccessSection
			LockdownSection(lockdown: lockdown, showLockNowAlert: $showLockNowAlert)
			if let saveError {
				Section {
					Label(saveError, systemImage: "exclamationmark.triangle.fill")
						.font(.footnote)
						.foregroundStyle(.orange)
				}
			}
			Section("Diagnostics") {
				Toggle(isOn: $serialEnabled) {
					Label("Serial Console", systemImage: "terminal")
					Text("Serial Console over the Stream API.")
				}
				.tint(.accentColor)
				Toggle(isOn: $debugLogApiEnabled) {
					Label("Debug Logs", systemImage: "ant.fill")
					Text("Output live debug logging over serial, view and export position-redacted device logs over Bluetooth.")
				}
				.tint(.accentColor)
			}
			Section {
				Toggle(isOn: $isManaged) {
					Label("Managed Device", systemImage: "gearshape.arrow.triangle.2.circlepath")
				}
				.tint(.accentColor)
				.disabled(adminKey.isEmpty)
				if adminKey.isEmpty {
					Label("An admin key must be set before enabling managed mode.", systemImage: "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			} header: {
				Text("Administration")
			} footer: {
				Text("Managed devices cannot be configured locally. A primary admin key is required.")
			}
		}
		.disabled(!accessoryManager.isConnected || node?.securityConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					if !hasValidDeviceIdentity || !hasValidAdminKey || !hasValidAdminKey2 || !hasValidAdminKey3 {
						return
					}

					guard let deviceNum = accessoryManager.activeDeviceNum,
						  let connectedNode = getNodeInfo(id: deviceNum, context: context),
						  let fromUser = connectedNode.user,
						  let toUser = node?.user else {
						return
					}

					var config = Config.SecurityConfig()
					config.privateKey = preservedPrivateKey
					config.adminKey = [Data(base64Encoded: adminKey) ?? Data(), Data(base64Encoded: adminKey2) ?? Data(), Data(base64Encoded: adminKey3) ?? Data()]
					config.isManaged = isManaged
					config.serialEnabled = serialEnabled
					config.debugLogApiEnabled = debugLogApiEnabled
					// Always written back, even when the capability gate hid the control, so a policy
					// the radio already holds round-trips untouched instead of being reset to Compatible.
					config.packetSignaturePolicy = packetAuthenticitySelection.selected

					saveError = nil
					Task { @MainActor in
						do {
							_ = try await accessoryManager.saveSecurityConfig(
								config: config,
								fromUser: fromUser,
								toUser: toUser
							)
							hasChanges = false
							goBack()
						} catch {
							saveError = error.localizedDescription
						}
					}
				}
				.disabled(!hasValidDeviceIdentity)
			}
		}
		.scrollDismissesKeyboard(.immediately)
		.navigationTitle("Security Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onChange(of: node) { _, _ in
			setSecurityValues()
		}
		.onChange(of: isManaged) { _, newIsManaged in
			if newIsManaged != node?.securityConfig?.isManaged { hasChanges = true }
		}
		.onChange(of: serialEnabled) { _, newSerialEnabled in
			if newSerialEnabled != node?.securityConfig?.serialEnabled { hasChanges = true }
		}
		.onChange(of: debugLogApiEnabled) { _, newDebugLogApiEnabled in
			if newDebugLogApiEnabled != node?.securityConfig?.debugLogApiEnabled { hasChanges = true }
		}
		.onChange(of: packetAuthenticitySelection.selected) { _, policy in packetAuthenticityDidChange(to: policy) }
		.onChange(of: adminKey) { _, key in
			let tempKey = Data(base64Encoded: key) ?? Data()
			if key.isEmpty {
				hasValidAdminKey = true
			} else if tempKey.count == 32 {
				hasValidAdminKey = true
			} else {
				hasValidAdminKey = false
			}
			if key != node?.securityConfig?.adminKey?.base64EncodedString() ?? "" && hasValidAdminKey { hasChanges = true }
		}
		.onChange(of: adminKey2) { _, key in
			let tempKey = Data(base64Encoded: key) ?? Data()
			if key.isEmpty {
				hasValidAdminKey2 = true
			} else if tempKey.count == 32 {
				hasValidAdminKey2 = true
			} else {
				hasValidAdminKey2 = false
			}
			if key != node?.securityConfig?.adminKey2?.base64EncodedString() ?? "" && hasValidAdminKey2 { hasChanges = true }
		}
		.onChange(of: adminKey3) { _, key in
			let tempKey = Data(base64Encoded: key) ?? Data()
			if key.isEmpty {
				hasValidAdminKey3 = true
			} else if tempKey.count == 32 {
				hasValidAdminKey3 = true
			} else {
				hasValidAdminKey3 = false
			}
			if key != node?.securityConfig?.adminKey3?.base64EncodedString() ?? "" && hasValidAdminKey3 { hasChanges = true }
		}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.securityConfig == nil },
				request: accessoryManager.requestSecurityConfig
			)
		}
	}

	func setSecurityValues() {
		self.publicKey = node?.securityConfig?.publicKey?.base64EncodedString() ?? ""
		self.preservedPrivateKey = node?.securityConfig?.privateKey ?? Data()
		self.adminKey = node?.securityConfig?.adminKey?.base64EncodedString(options: .lineLength64Characters) ?? ""
		self.adminKey2 = node?.securityConfig?.adminKey2?.base64EncodedString(options: .lineLength64Characters) ?? ""
		self.adminKey3 = node?.securityConfig?.adminKey3?.base64EncodedString(options: .lineLength64Characters) ?? ""
		self.isManaged = node?.securityConfig?.isManaged ?? false
		self.serialEnabled = node?.securityConfig?.serialEnabled ?? false
		self.debugLogApiEnabled = node?.securityConfig?.debugLogApiEnabled ?? false
		self.packetAuthenticitySelection = storedPacketAuthenticitySelection
		self.backupStatus = nil
		self.saveError = nil
		self.isPrivateKeyRevealed = false
		self.hasChanges = false
	}

	private var deviceIdentitySection: some View {
		Section("Device Identity") {
			HStack(alignment: .firstTextBaseline) {
				Label("Public Key", systemImage: "key")
				Spacer()
				Button {
					UIPasteboard.general.string = publicKey
				} label: {
					Label("Copy", systemImage: "doc.on.doc")
				}
				.buttonStyle(.bordered)
				.controlSize(.small)
				.disabled(publicKey.isEmpty)
			}
			if publicKey.isEmpty {
				Label("This device has not reported a public key.", systemImage: "exclamationmark.triangle.fill")
					.font(.footnote)
					.foregroundStyle(.orange)
			} else {
				Text(publicKey)
					.font(.system(.footnote, design: .monospaced))
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
			}
			if !hasValidDeviceIdentity {
				Label("Security settings cannot be saved until this device reports a valid identity key pair.", systemImage: "exclamationmark.triangle.fill")
					.font(.footnote)
					.foregroundStyle(.orange)
			}
			Text("This public key identifies your device to other nodes. The device manages its identity, so it cannot be changed from the app.")
				.font(.footnote)
				.foregroundStyle(.secondary)
			HStack(alignment: .firstTextBaseline) {
				Label("Private Key", systemImage: "key.fill")
				Spacer()
				Button {
					isPrivateKeyRevealed.toggle()
				} label: {
					Label(
						isPrivateKeyRevealed ? "Hide" : "Show",
						systemImage: isPrivateKeyRevealed ? "eye.slash" : "eye"
					)
				}
				.buttonStyle(.bordered)
				.controlSize(.small)
				.disabled(privateKey.isEmpty)
				if isPrivateKeyRevealed {
					Button {
						UIPasteboard.general.string = privateKey
					} label: {
						Label("Copy", systemImage: "doc.on.doc")
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
				}
			}
			if privateKey.isEmpty {
				Label("This device has not reported a private key.", systemImage: "exclamationmark.triangle.fill")
					.font(.footnote)
					.foregroundStyle(.orange)
			} else if isPrivateKeyRevealed {
				Text(privateKey)
					.font(.system(.footnote, design: .monospaced))
					.foregroundStyle(.secondary)
					.privacySensitive()
					.textSelection(.enabled)
			} else {
				Text(String(repeating: "*", count: 16))
					.font(.system(.footnote, design: .monospaced))
					.foregroundStyle(.secondary)
					.privacySensitive()
			}
			Text("This private key is hidden until you choose Show. It is read-only and cannot be changed from the app.")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}

	private var adminAccessSection: some View {
		Section {
			AdminKeyInput(title: "Primary Admin Key", key: $adminKey, isValid: $hasValidAdminKey)
			AdminKeyInput(title: "Secondary Admin Key", key: $adminKey2, isValid: $hasValidAdminKey2)
			AdminKeyInput(title: "Tertiary Admin Key", key: $adminKey3, isValid: $hasValidAdminKey3)
		} header: {
			Text("Admin Access")
		} footer: {
			Text("These public keys authorize administration of this device.")
		}
	}

	private var identityBackupSection: some View {
		Section("Identity Backup") {
			HStack(alignment: .firstTextBaseline) {
				Label("Key Pair Backup", systemImage: "icloud")
				Spacer()
				Button(action: backupIdentityKeyPair) {
					Label("Back Up", systemImage: "icloud.and.arrow.up")
				}
				.buttonStyle(.bordered)
				.controlSize(.small)
				.disabled(!hasValidDeviceIdentity)
			}
			if let backupStatus {
				Label(backupStatus.description, systemImage: backupStatus.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
					.font(.footnote)
					.foregroundStyle(backupStatus.success ? .green : .orange)
			}
			Text("Stores this device's public and private identity keys in your iCloud Keychain. Backing up does not change the device identity.")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}

	private func backupIdentityKeyPair() {
		guard let node,
			  let publicKey = node.securityConfig?.publicKey,
			  IdentityKeyPairBackup.isValid(
				privateKey: preservedPrivateKey,
				publicKey: publicKey
			  ),
			  let encodedBackup = try? JSONEncoder().encode(
				IdentityKeyPairBackup(privateKey: preservedPrivateKey, publicKey: publicKey)
			  ),
			  let backupValue = String(data: encodedBackup, encoding: .utf8) else {
			backupStatus = .saveFailed
			return
		}

		let status = KeychainHelper.standard.save(
			key: "IdentityKeyPairNode\(node.num)",
			value: backupValue
		)
		backupStatus = status == errSecSuccess ? .saved : .saveFailed
	}
}

private struct AdminKeyInput: View {
	let title: String
	@Binding var key: String
	@Binding var isValid: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Label(title, systemImage: "key.viewfinder")
			SecureInput(title, text: $key, isValid: $isValid)
				.background(
					RoundedRectangle(cornerRadius: 10.0)
						.stroke(isValid ? Color.clear : Color.red, lineWidth: 2.0)
				)
		}
		.padding(.vertical, 2)
	}
}

// MARK: - Lockdown section (MESHTASTIC_LOCKDOWN-hardened firmware)

/// Settings section surfacing lockdown session status, Lock Now, and Forget
/// Stored Passphrase. Hidden when the connected device does not report any
/// lockdown state (i.e. non-hardened firmware that never sends LockdownStatus).
private struct LockdownSection: View {
	@ObservedObject var lockdown: LockdownCoordinator
	@Binding var showLockNowAlert: Bool

	var body: some View {
		switch lockdown.state {
		case .unlocked(let bootsRemaining, let validUntilEpoch):
			Section(header: Text("Lockdown")) {
				Label {
					VStack(alignment: .leading) {
						Text("Session status")
						Text("Unlocked")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				} icon: {
					Image(systemName: "lock.open.fill")
						.foregroundStyle(.green)
				}

				if bootsRemaining > 0 {
					Label("Boots remaining: \(bootsRemaining)", systemImage: "powerplug")
				}

				if validUntilEpoch == 0 {
					Label("No time limit", systemImage: "infinity")
				} else {
					Label {
						Text("Expires \(Date(timeIntervalSince1970: TimeInterval(validUntilEpoch)).formatted(date: .abbreviated, time: .shortened))")
					} icon: {
						Image(systemName: "clock")
					}
				}

				Button(role: .destructive) {
					showLockNowAlert = true
				} label: {
					Label("Lock Now", systemImage: "lock.fill")
				}
				.alert("Lock device now?", isPresented: $showLockNowAlert) {
					Button("Cancel", role: .cancel) {}
					Button("Lock", role: .destructive) {
						lockdown.lockNow()
					}
				} message: {
					Text("This revokes the current session and reboots the device locked. You will need the passphrase to reconnect.")
				}

				Button {
					lockdown.forgetCachedPassphrase()
				} label: {
					Label("Forget Stored Passphrase", systemImage: "key.slash")
				}
			}
		case .none:
			// Non-lockdown firmware or pre-handshake. Hide the section entirely.
			EmptyView()
		default:
			// .needsProvision / .locked / .unlockFailed / .unlockBackoff are
			// surfaced via the full-screen sheet in ContentView; do not
			// duplicate them in Settings.
			EmptyView()
		}
	}
}

#Preview {
	SecurityConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.environmentObject(LockdownCoordinator())
		.modelContainer(PersistenceController.preview.container)
}
