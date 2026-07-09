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
import OSLog
import CryptoKit

struct PacketAuthenticitySelectionState {
	private(set) var selected: Config.SecurityConfig.PacketSignaturePolicy
	private(set) var pendingStrict = false

	init(selected: Config.SecurityConfig.PacketSignaturePolicy = .balanced) {
		self.selected = selected
	}

	mutating func propose(_ policy: Config.SecurityConfig.PacketSignaturePolicy) {
		guard policy == .strict, selected != .strict else {
			selected = policy
			pendingStrict = false
			return
		}

		pendingStrict = true
	}

	mutating func confirmStrict() {
		guard pendingStrict else { return }
		selected = .strict
		pendingStrict = false
	}

	mutating func cancelStrict() {
		pendingStrict = false
	}
}

enum PacketAuthenticityCapability: Equatable {
	case supported
	case unsupported
	case unknown

	init(metadata: DeviceMetadataEntity?) {
		guard let metadata else {
			self = .unknown
			return
		}

		self = metadata.hasXeddsa ? .supported : .unsupported
	}

	var allowsChanges: Bool {
		self == .supported
	}

	var unavailableDescription: String? {
		switch self {
		case .supported:
			return nil
		case .unsupported:
			return String(
				localized: "This firmware build does not include XEdDSA packet signing, so this setting is unavailable.",
				comment: "Explanation shown when packet authenticity controls are unavailable on the connected radio."
			)
		case .unknown:
			return String(
				localized: "The device has not reported XEdDSA capability. Update its firmware before changing this setting.",
				comment: "Explanation shown when an older radio has not reported packet-signing capability."
			)
		}
	}
}

extension Config.SecurityConfig.PacketSignaturePolicy {
	static let packetAuthenticityOptions: [Self] = [
		.compatible,
		.balanced,
		.strict
	]

	var packetAuthenticityTitle: String {
		switch self {
		case .compatible:
			return String(localized: "Compatible — Accept unsigned", comment: "Compatible packet authenticity policy option.")
		case .balanced:
			return String(localized: "Balanced — Prefer authenticated", comment: "Balanced packet authenticity policy option.")
		case .strict:
			return String(localized: "Strict — Require authentication", comment: "Strict packet authenticity policy option.")
		case .UNRECOGNIZED:
			return String(localized: "Unknown policy", comment: "Fallback title for an unrecognized packet authenticity policy.")
		}
	}

	var packetAuthenticityDescription: String {
		switch self {
		case .compatible:
			return String(
				localized: "Verifies authentication when present and accepts unsigned traffic for maximum compatibility.",
				comment: "Description of the Compatible packet authenticity policy."
			)
		case .balanced:
			return String(
				localized: "Recommended. Rejects unsigned, signable broadcasts from nodes known to sign while accepting legacy unsigned traffic.",
				comment: "Description of the default Balanced packet authenticity policy."
			)
		case .strict:
			return String(
				localized: "Only processes remote mesh packets authenticated by a verified XEdDSA signature or successful PKI decryption. Unsigned positions, messages, telemetry, and other traffic are ignored; unsigned traffic from older or licensed (ham) nodes and packets too large to sign may disappear.",
				comment: "Description of the Strict packet authenticity policy."
			)
		case .UNRECOGNIZED:
			return String(
				localized: "This device reported a packet authenticity policy that this app version does not recognize.",
				comment: "Description shown for an unrecognized packet authenticity policy."
			)
		}
	}
}

private struct PacketAuthenticitySection: View {
	let idiom: UIUserInterfaceIdiom
	let capability: PacketAuthenticityCapability
	@Binding var selection: PacketAuthenticitySelectionState
	@Binding var showStrictConfirmation: Bool

	var body: some View {
		Section(header: Text(String(localized: "Packet Authenticity", comment: "Security settings section title."))) {
			Picker(
				String(localized: "Protection Level", comment: "Label for the packet authenticity policy picker."),
				selection: Binding(
					get: { selection.selected },
					set: { policy in
						selection.propose(policy)
						showStrictConfirmation = selection.pendingStrict
					}
				)
			) {
				ForEach(Config.SecurityConfig.PacketSignaturePolicy.packetAuthenticityOptions, id: \.rawValue) { policy in
					Text(policy.packetAuthenticityTitle)
						.tag(policy)
				}
			}
			.disabled(!capability.allowsChanges)
			.alert(String(localized: "Require authentication for all remote packets?", comment: "Strict packet authenticity confirmation title."), isPresented: $showStrictConfirmation) {
				Button(String(localized: "Cancel"), role: .cancel) {
					selection.cancelStrict()
				}
				Button(String(localized: "Use Strict", comment: "Confirms enabling the Strict packet authenticity policy."), role: .destructive) {
					selection.confirmStrict()
				}
			} message: {
				Text(String(
					localized: "Strict accepts only remote packets with a verified XEdDSA signature or successful PKI decryption. Unsigned positions, messages, telemetry, and other traffic from older firmware or nodes, licensed (ham) nodes, and packets too large to sign will be rejected. Authenticated PKI direct messages remain available.",
					comment: "Warning shown before enabling the Strict packet authenticity policy."
				))
			}

			Text(selection.selected.packetAuthenticityDescription)
				.foregroundStyle(.secondary)
				.font(idiom == .phone ? .caption : .callout)

			if let unavailableDescription = capability.unavailableDescription {
				Label(
					unavailableDescription,
					systemImage: "exclamationmark.triangle.fill"
				)
				.font(.caption)
				.foregroundStyle(.orange)
			}
		}
	}
}

struct SecurityConfig: View {

	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var lockdown: LockdownCoordinator
	@Environment(\.dismiss) private var goBack

	@State private var showLockNowAlert: Bool = false
	
	let node: NodeInfoEntity?
	
	@State var hasChanges = false
	@State var publicKey = ""
	@State var privateKey = ""
	@State var hasValidPrivateKey: Bool = false
	@State var adminKey: String = ""
	@State var adminKey2: String = ""
	@State var adminKey3: String = ""
	@State var hasValidAdminKey: Bool = true
	@State var hasValidAdminKey2: Bool = true
	@State var hasValidAdminKey3: Bool = true
	@State var isManaged = false
	@State var serialEnabled = false
	@State var debugLogApiEnabled = false
	@State var packetAuthenticitySelection = PacketAuthenticitySelectionState()
	@State var showStrictPolicyConfirmation = false
	@State var privateKeyIsSecure = true
	@State var backupStatus: KeyBackupStatus?
	@State var backupStatusError: OSStatus?
	
	private var isValidKeyPair: Bool {
		guard let privateKeyBytes = Data(base64Encoded: privateKey),
			  let calculatedPublicKey = generatePublicKeyDisplay(from: privateKeyBytes),
			  let decodedPublicKey = Data(base64Encoded: publicKey) else {
			return false
		}
		return calculatedPublicKey == decodedPublicKey
	}

	private var packetAuthenticityCapability: PacketAuthenticityCapability {
		PacketAuthenticityCapability(metadata: node?.metadata)
	}
	
	var body: some View {
		Form {
			ConfigHeader(title: "Security", config: \.securityConfig, node: node, onAppear: setSecurityValues)
			Text("Security Config Settings require a firmware version 2.5+")
				.font(.title3)
			Section(header: Text("Direct Message Key")) {
				VStack(alignment: .leading) {
					HStack(alignment: .firstTextBaseline) {
						Label("Public Key", systemImage: "key")
						Spacer()
						// Explicit copy action. On Mac Catalyst `.textSelection(.enabled)` on a
						// Text inside a Form does not reliably offer a right-click "Copy", so the
						// selection-only approach left macOS users unable to copy their key (#1943).
						Button {
							UIPasteboard.general.string = publicKey
						} label: {
							Image(systemName: "doc.on.doc")
							Text("Copy")
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.small)
						.disabled(publicKey.isEmpty)
					}
					Text(publicKey)
						.font(idiom == .phone ? .caption : .callout)
						.allowsTightening(true)
						.monospaced()
						.keyboardType(.alphabet)
						.foregroundStyle(.tertiary)
						.disableAutocorrection(true)
						// Retained as the iOS copy path (long-press to select); the Copy button
						// above is the reliable path on Mac Catalyst, where this doesn't offer
						// a right-click "Copy" inside a Form (#1943).
						.textSelection(.enabled)
						.background(
							RoundedRectangle(cornerRadius: 10.0)
								.stroke(isValidKeyPair ? Color.clear : Color.red, lineWidth: 2.0)
						)
					Text("Your public key is generated from your private key and sent to other nodes on the mesh so they can compute a shared secret key with you.")
						.foregroundStyle(.secondary)
						.font(idiom == .phone ? .caption : .callout)
					Divider()
					Label("Private Key", systemImage: "key.fill")
					SecureInput("Private Key", text: $privateKey, isValid: $hasValidPrivateKey, isSecure: $privateKeyIsSecure)
						.background(
							RoundedRectangle(cornerRadius: 10.0)
								.stroke(hasValidPrivateKey ? Color.clear : Color.red, lineWidth: 2.0)
						)
					Text("Used to create a shared key with a remote device.")
						.foregroundStyle(.secondary)
						.font(idiom == .phone ? .caption : .callout)
					if let currentNode = node {
						Divider()
						Label("Key Backup", systemImage: "icloud")
						HStack(alignment: .firstTextBaseline) {
							let keychainKey = "PrivateKeyNode\(currentNode.num)"
							Button {
								let status = KeychainHelper.standard.save(key: keychainKey, value: privateKey)
								if status == errSecSuccess {
									backupStatus = KeyBackupStatus.saved
								} else {
									backupStatus = KeyBackupStatus.saveFailed
									backupStatusError = status
								}
							}
							label: {
								Image(systemName: "icloud.and.arrow.up")
								Text("Backup")
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.small)
							Spacer()
							Button {
								if let value = KeychainHelper.standard.read(key: keychainKey) {
									self.privateKey = value
									self.privateKeyIsSecure = false
									backupStatus = KeyBackupStatus.restored
								} else {
									backupStatus = KeyBackupStatus.restoreFailed
								}
							}
							label: {
								Image(systemName: "key.icloud")
								Text("Restore")
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.small)
							Spacer()
							Button {
								let status = KeychainHelper.standard.delete(key: keychainKey)
								if status == errSecSuccess {
									backupStatus = KeyBackupStatus.deleted
								} else {
									backupStatus = KeyBackupStatus.deleteFailed
								}
							}
							label: {
								Image(systemName: "trash")
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.small)
							.accessibilityLabel(String(localized: "Delete key backup", comment: "VoiceOver label for the delete key backup button"))
						}
						if let status = backupStatus {
							let state = status.success
							Text("\(status.description)")
								.font(.caption)
								.foregroundColor(state ? .green : .red)
						}
						Text("Backup your private key to your iCloud keychain.")
							.foregroundStyle(.secondary)
							.font(idiom == .phone ? .caption : .callout)
					}
					Divider()
					HStack(alignment: .firstTextBaseline) {
						Label("Regenerate Private Key", systemImage: "arrow.clockwise.circle")
						Spacer()
						Button {
							if let keyBytes = generatePrivateKey(count: 32) {
								privateKey = keyBytes.base64EncodedString()
								self.privateKeyIsSecure = false
							}
						} label: {
							Image(systemName: "lock.rotation")
								.font(.title)
						}
						.buttonStyle(.bordered)
						.buttonBorderShape(.capsule)
						.controlSize(.small)
						.accessibilityLabel(String(localized: "Regenerate private key", comment: "VoiceOver label for the regenerate private key button"))
					}
					Text("Generate a new private key to replace the one currently in use. The public key will automatically be regenerated from your private key.")
						.foregroundStyle(.secondary)
						.font(idiom == .phone ? .caption : .callout)
				}
			}
			PacketAuthenticitySection(
				idiom: idiom,
				capability: packetAuthenticityCapability,
				selection: $packetAuthenticitySelection,
				showStrictConfirmation: $showStrictPolicyConfirmation
			)
			Section(header: Text("Admin Keys")) {
				Label("Primary Admin Key", systemImage: "key.viewfinder")
				SecureInput("Primary Admin Key", text: $adminKey, isValid: $hasValidAdminKey)
					.background(
						RoundedRectangle(cornerRadius: 10.0)
							.stroke(hasValidAdminKey ? Color.clear : Color.red, lineWidth: 2.0)
					)
				Text("The primary public key authorized to send admin messages to this node.")
					.foregroundStyle(.secondary)
					.font(idiom == .phone ? .caption : .callout)
				Label("Secondary Admin Key", systemImage: "key.viewfinder")
				SecureInput("Secondary Admin Key", text: $adminKey2, isValid: $hasValidAdminKey2)
					.background(
						RoundedRectangle(cornerRadius: 10.0)
							.stroke(hasValidAdminKey2 ? Color.clear : Color.red, lineWidth: 2.0)
					)
				Text("The secondary public key authorized to send admin messages to this node.")
					.foregroundStyle(.secondary)
					.font(idiom == .phone ? .caption : .callout)
				Label("Tertiary Admin Key", systemImage: "key.viewfinder")
				SecureInput("Tertiary Admin Key", text: $adminKey3, isValid: $hasValidAdminKey3)
					.background(
						RoundedRectangle(cornerRadius: 10.0)
							.stroke(hasValidAdminKey3 ? Color.clear : Color.red, lineWidth: 2.0)
					)
				Text("The tertiary public key authorized to send admin messages to this node.")
					.foregroundStyle(.secondary)
					.font(idiom == .phone ? .caption : .callout)
			}
			LockdownSection(lockdown: lockdown, showLockNowAlert: $showLockNowAlert)

			Section(header: Text("Logs")) {
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
			Section(header: Text("Administration")) {
				Toggle(isOn: $isManaged) {
					Label("Managed Device", systemImage: "gearshape.arrow.triangle.2.circlepath")
					Text("Device is managed by a mesh administrator, the user is unable to access any of the device settings.")
				}
				.tint(.accentColor)
				.disabled(adminKey.length == 0)
				if adminKey.length == 0 {
					Label("An admin key must be set before enabling managed mode.", systemImage: "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			}
		}
		.disabled(!accessoryManager.isConnected || node?.securityConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					
					if !hasValidPrivateKey || !hasValidAdminKey || !hasValidAdminKey2 || !hasValidAdminKey3 {
						return
					}
					
					guard let deviceNum = accessoryManager.activeDeviceNum,
						  let connectedNode = getNodeInfo(id: deviceNum, context: context),
						  let fromUser = connectedNode.user,
						  let toUser = node?.user else {
						return
					}
					
					var config = Config.SecurityConfig()
					config.privateKey = Data(base64Encoded: privateKey) ?? Data()
					config.adminKey = [Data(base64Encoded: adminKey) ?? Data(), Data(base64Encoded: adminKey2) ?? Data(), Data(base64Encoded: adminKey3) ?? Data()]
					config.isManaged = isManaged
					config.serialEnabled = serialEnabled
					config.debugLogApiEnabled = debugLogApiEnabled
					config.packetSignaturePolicy = packetAuthenticitySelection.selected
					
					let keyUpdated = node?.securityConfig?.privateKey?.base64EncodedString() ?? "" != privateKey
					Task {
						_ = try await accessoryManager.saveSecurityConfig(
							config: config,
							fromUser: fromUser,
							toUser: toUser
						)
						Task { @MainActor in
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							if keyUpdated {
								// This is the *local* node's own keypair being changed deliberately by the user in the
								// Security config screen (gated behind `keyUpdated` + an explicit save), not an inbound
								// mesh key — so the first-wins protection doesn't apply. `keyMatch`/`newPublicKey` track
								// *remote* contacts' keys, so they are intentionally left untouched here.
								node?.user?.publicKey = Data(base64Encoded: publicKey) ?? Data()
								do {
									try context.save()
									Logger.data.info("💾 Saved UserEntity Public Key to Core Data for \(node?.num ?? 0, privacy: .public)")
								} catch {
									let nsError = error as NSError
									Logger.data.error("Error Updating UserEntity: \(nsError, privacy: .public)")
								}
							}
						}
						hasChanges = false
						if keyUpdated {
							Task {
								do {
									try await accessoryManager.sendReboot(
										fromUser: fromUser,
										toUser: toUser
									)
								} catch {
									Logger.mesh.warning("Reboot Failed")
								}
							}
						}
						goBack()
					}
				}
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
		.onChange(of: packetAuthenticitySelection.selected) { _, newPolicy in
			if Int32(newPolicy.rawValue) != node?.securityConfig?.packetSignaturePolicy { hasChanges = true }
		}
		.onChange(of: privateKey) { _, key in
			let tempKey = Data(base64Encoded: privateKey) ?? Data()
			if tempKey.count == 32 {
				hasValidPrivateKey = true
				if let privateKeyBytes = Data(base64Encoded: privateKey), privateKeyBytes.count == 32 {
					// Valid private key -- generate the public key
					publicKey = generatePublicKeyDisplay(from: privateKeyBytes)?.base64EncodedString() ?? ""
				}
			} else {
				hasValidPrivateKey = false
			}
			if key != node?.securityConfig?.privateKey?.base64EncodedString() ?? "" && hasValidPrivateKey { hasChanges = true }
		}
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
		self.privateKey = node?.securityConfig?.privateKey?.base64EncodedString() ?? ""
		self.adminKey = node?.securityConfig?.adminKey?.base64EncodedString(options: .lineLength64Characters) ?? ""
		self.adminKey2 = node?.securityConfig?.adminKey2?.base64EncodedString(options: .lineLength64Characters) ?? ""
		self.adminKey3 = node?.securityConfig?.adminKey3?.base64EncodedString(options: .lineLength64Characters) ?? ""
		self.isManaged = node?.securityConfig?.isManaged ?? false
		self.serialEnabled = node?.securityConfig?.serialEnabled ?? false
		self.debugLogApiEnabled = node?.securityConfig?.debugLogApiEnabled ?? false
		self.packetAuthenticitySelection = PacketAuthenticitySelectionState(
			selected: Config.SecurityConfig.PacketSignaturePolicy(
				rawValue: Int(node?.securityConfig?.packetSignaturePolicy ?? 0)
			) ?? .balanced
		)
		self.hasChanges = false
	}
	
	func generatePrivateKey(count: Int) -> Data? {
		var randomBytes = Data(count: count)
		let status = randomBytes.withUnsafeMutableBytes { (mutableBytes: UnsafeMutableRawBufferPointer) -> Int32 in
			guard let pointer = mutableBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
				return -1 // Indicate an error
			}
			return SecRandomCopyBytes(kSecRandomDefault, count, pointer)
		}
		
		if status == errSecSuccess {
			// Generate a random "f" value and then adjust the value to make
			// it valid as an "s" value for eval().  According to the specification
			// we need to mask off the 3 right-most bits of f[0], mask off the
			// left-most bit of f[31], and set the second to left-most bit of f[31].
			var f = randomBytes
			f[0] &= 0xF8
			f[31] = (f[31] & 0x7F) | 0x40
			return f
		} else {
			// Handle error, perhaps by logging or throwing an exception
			Logger.mesh.debug("Error generating random bytes: \(status)")
			return nil
		}
	}
	
	// Generate a new public key for display purposes to show the user what will be changed after the new private key is saved to the device
	func generatePublicKeyDisplay(from privateKeyData: Data) -> Data? {
		guard privateKeyData.count == 32 else {
			Logger.mesh.debug("Invalid private key length. Must be 32 bytes for Curve25519.")
			return nil
		}
		
		do {
			// Create a Curve25519 private key from raw representation
			let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
			let publicKey = privateKey.publicKey
			return publicKey.rawRepresentation
		} catch {
			Logger.mesh.debug("Failed to create Curve25519 key: \(error)")
			return nil
		}
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

private struct PacketAuthenticitySectionPreview: View {
	let capability: PacketAuthenticityCapability
	@State private var selection = PacketAuthenticitySelectionState()
	@State private var showStrictConfirmation = false

	var body: some View {
		Form {
			PacketAuthenticitySection(
				idiom: UIDevice.current.userInterfaceIdiom,
				capability: capability,
				selection: $selection,
				showStrictConfirmation: $showStrictConfirmation
			)
		}
	}
}

#Preview("Packet Authenticity — iPhone Light") {
	PacketAuthenticitySectionPreview(capability: .supported)
		.preferredColorScheme(.light)
		.previewDevice("iPhone 16 Pro")
}

#Preview("Packet Authenticity — iPhone Dark") {
	PacketAuthenticitySectionPreview(capability: .supported)
		.preferredColorScheme(.dark)
		.previewDevice("iPhone 16 Pro")
}

#Preview("Packet Authenticity — iPad Unsupported") {
	PacketAuthenticitySectionPreview(capability: .unsupported)
		.preferredColorScheme(.light)
		.previewDevice("iPad Pro (11-inch) (M4)")
}

#Preview {
	SecurityConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.environmentObject(LockdownCoordinator())
		.modelContainer(PersistenceController.preview.container)
}
