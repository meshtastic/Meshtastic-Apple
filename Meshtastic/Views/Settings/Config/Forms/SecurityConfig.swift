//
//  SecurityConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import SwiftUI
import MeshtasticProtobufs
import OSLog
import CryptoKit

extension Config.SecurityConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, SecurityConfigEntity?> = \NodeInfoEntity.securityConfig

	init(entity: SecurityConfigEntity) {
		self.init()
		publicKey = entity.publicKey ?? Data()
		privateKey = entity.privateKey ?? Data()
		isManaged = entity.isManaged
		serialEnabled = entity.serialEnabled
		debugLogApiEnabled = entity.debugLogApiEnabled
		adminChannelEnabled = entity.adminChannelEnabled
		packetSignaturePolicy = PacketSignaturePolicy(rawValue: Int(entity.packetSignaturePolicy)) ?? .compatible
		// Three stored columns, one repeated field. The empty slots travel too, because
		// the firmware reads the array positionally: dropping a blank would move a key.
		adminKey = [entity.adminKey ?? Data(), entity.adminKey2 ?? Data(), entity.adminKey3 ?? Data()]
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

/// A 32-byte key, as typed and as stored.
enum SecurityKey {
	static let byteCount = 32
	static let slots = 3

	/// Blank is allowed and means unset. Anything else must decode to exactly 32 bytes,
	/// which is what the firmware expects; shorter or malformed is a typo, not a key.
	static func isValid(_ text: String) -> Bool {
		if text.isEmpty { return true }
		return Data(base64Encoded: text)?.count == byteCount
	}

	static func data(_ text: String) -> Data {
		guard let data = Data(base64Encoded: text), data.count == byteCount else { return Data() }
		return data
	}

	static func text(_ data: Data) -> String {
		data.isEmpty ? "" : data.base64EncodedString()
	}

	/// The admin key array padded to its fixed slot count, so a row can address a slot
	/// that the radio has not filled in yet.
	static func padded(_ keys: [Data]) -> [Data] {
		var keys = keys
		while keys.count < slots { keys.append(Data()) }
		return Array(keys.prefix(slots))
	}
}

struct SecurityConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@EnvironmentObject private var lockdown: LockdownCoordinator
	@State private var showLockNowAlert = false
	let node: NodeInfoEntity?

	private typealias F = Config.SecurityConfig.Fields

	/// `admin_key` is repeated, so the generator emits no typed descriptor for it. The
	/// erased one carries the identity settings search needs.
	private static var adminKeyField: AnyConfigField<Config.SecurityConfig> {
		Config.SecurityConfig.allFields.first { $0.tag == 3 }!
	}

	static func overlay(node: NodeInfoEntity? = nil) -> ConfigFormOverlay<Config.SecurityConfig> {
		.init(sections: [
			.init(title: String(localized: "Direct Message Key", comment: "Settings section"), fields: [
				// Laid out rather than buried in a leading section so settings search can
				// land on them. The controls are custom; the words are the schema's.
				.init(unsupported: F.publicKey,
					  control: .custom { config in AnyView(PublicKeyRow(config: config)) }, symbol: "key"),
				.init(unsupported: F.privateKey,
					  control: .custom { config in AnyView(PrivateKeyRows(config: config, node: node)) }, symbol: "key.fill")
			]),
			.init(title: String(localized: "Admin Keys", comment: "Settings section"), fields: [
				.init(repeated: Self.adminKeyField,
					  control: .custom { config in AnyView(AdminKeyRows(config: config)) }, symbol: "key.viewfinder")
			]),
			.init(title: String(localized: "Logs", comment: "Settings section"), fields: [
				.init(F.serialEnabled, symbol: "terminal"),
				.init(F.debugLogApiEnabled, symbol: "ant.fill")
			]),
			.init(title: String(localized: "Administration", comment: "Settings section"), fields: [
				.init(F.isManaged, symbol: "gearshape.arrow.triangle.2.circlepath",
					  control: .custom { config in AnyView(ManagedDeviceRow(config: config)) })
			])
		], omitted: [
			.init(F.adminChannelEnabled, "not offered by this client; the legacy admin channel"),
			.init(F.packetSignaturePolicy,
				  "laid out by the Packet Authenticity section, which explains each level",
				  coveredBy: F.publicKey.identity)
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Security", overlay: Self.overlay(node: node),
			request: accessoryManager.requestSecurityConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveSecurityConfig(config: config, fromUser: from, toUser: to)
			},
			leading: { config in
				// Its own view with a per-level explanation, and unlabelled upstream, so it
				// stays a section rather than becoming a row. A plain binding to the message
				// now that choosing a level commits straight away.
				PacketAuthenticitySection(
					capability: PacketAuthenticityCapability(metadata: node?.metadata),
					isConnected: accessoryManager.isConnected,
					policy: config.packetSignaturePolicy)
			},
			trailing: { _ in
				LockdownSection(lockdown: lockdown, showLockNowAlert: $showLockNowAlert)
			})
		.navigationTitle("Security Config")
	}
}

/// The public key, derived from the private one rather than typed. Shown with an
/// explicit Copy button: on Mac Catalyst, text selection inside a Form does not reliably
/// offer a right-click Copy, which left macOS users unable to copy their key (#1943).
private struct PublicKeyRow: View {
	@Binding var config: Config.SecurityConfig
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	private static let metadata = FieldMetadataRegistry.get("meshtastic.Config.SecurityConfig", tag: 1)

	private var text: String { SecurityKey.text(config.publicKey) }

	/// Whether the key on screen is the one this private key produces. A mismatch means
	/// the pair will not decrypt anything, so it is worth showing before a save.
	private var matchesPrivateKey: Bool {
		guard !config.privateKey.isEmpty else { return true }
		guard let derived = generatePublicKeyDisplay(from: config.privateKey) else { return false }
		return derived == config.publicKey
	}

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Label(Self.metadata?.label ?? "Public Key", systemImage: "key")
				Spacer()
				Button {
					UIPasteboard.general.string = text
				} label: {
					Image(systemName: "doc.on.doc")
					Text("Copy")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
				.disabled(text.isEmpty)
			}
			Text(text)
				.font(idiom == .phone ? .caption : .callout)
				.allowsTightening(true)
				.monospaced()
				.foregroundStyle(.tertiary)
				.textSelection(.enabled)
				.background(
					RoundedRectangle(cornerRadius: 10.0)
						.stroke(matchesPrivateKey ? Color.clear : Color.red, lineWidth: 2.0))
			if let description = Self.metadata?.description {
				Text(description)
					.foregroundStyle(.secondary)
					.font(idiom == .phone ? .caption : .callout)
			}
		}
	}
}

/// The private key, and the iCloud keychain backup that goes with it.
private struct PrivateKeyRows: View {
	@Binding var config: Config.SecurityConfig
	let node: NodeInfoEntity?
	@State private var text = ""
	@State private var isSecure = true
	@State private var backupStatus: KeyBackupStatus?
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	private static let metadata = FieldMetadataRegistry.get("meshtastic.Config.SecurityConfig", tag: 2)

	/// Blank is not a fault. Before the radio's values arrive the field is empty, and
	/// marking that red says there is something wrong with a key the user has not seen
	/// yet. Only text that is present and not a 32-byte key is wrong.
	private var isValid: Bool { SecurityKey.isValid(text) }

	var body: some View {
		VStack(alignment: .leading) {
			Label(Self.metadata?.label ?? "Private Key", systemImage: "key.fill")
			SecureInput(String(localized: "Private Key", comment: "Security setting"),
						text: $text, isValid: .constant(isValid), isSecure: $isSecure)
				.background(
					RoundedRectangle(cornerRadius: 10.0)
						.stroke(isValid ? Color.clear : Color.red, lineWidth: 2.0))
			if let description = Self.metadata?.description {
				Text(description)
					.foregroundStyle(.secondary)
					.font(idiom == .phone ? .caption : .callout)
			}
		}
		.onAppear { text = SecurityKey.text(config.privateKey) }
		.onChange(of: config.privateKey) { _, new in
			// The radio's values land after the row is on screen, so the field has to
			// follow them. Without this the key never appears at all.
			let incoming = SecurityKey.text(new)
			if incoming != text, SecurityKey.data(text) != new { text = incoming }
		}
		.onChange(of: text) { _, new in
			// A key that does not decode to 32 bytes stores as empty rather than as
			// itself: half a key is not a key, and writing one costs every existing
			// direct-message conversation.
			config.privateKey = SecurityKey.data(new)
			// The public key is derived, never typed, so it follows the private one.
			if !config.privateKey.isEmpty,
			   let derived = generatePublicKeyDisplay(from: config.privateKey) {
				config.publicKey = derived
			}
		}
		if let currentNode = node {
			KeyBackupRow(privateKey: $text, isSecure: $isSecure, status: $backupStatus, nodeNum: currentNode.num)
		}
	}
}

/// Backup, restore and delete for the private key in the iCloud keychain.
private struct KeyBackupRow: View {
	@Binding var privateKey: String
	@Binding var isSecure: Bool
	@Binding var status: KeyBackupStatus?
	let nodeNum: Int64
	@State private var statusError: OSStatus?

	private var keychainKey: String { "PrivateKeyNode\(nodeNum)" }

	var body: some View {
		VStack(alignment: .leading) {
			Label("Key Backup", systemImage: "icloud")
			HStack(alignment: .firstTextBaseline) {
				Button {
					let result = KeychainHelper.standard.save(key: keychainKey, value: privateKey)
					status = result == errSecSuccess ? .saved : .saveFailed
					statusError = result == errSecSuccess ? nil : result
				} label: {
					Image(systemName: "icloud.and.arrow.up")
					Text("Backup")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
				Spacer()
				Button {
					if let value = KeychainHelper.standard.read(key: keychainKey) {
						privateKey = value
						// Reveal what was restored: a key you cannot read back is one you
						// cannot check against the device you took it from.
						isSecure = false
						status = .restored
					} else {
						status = .restoreFailed
					}
				} label: {
					Image(systemName: "key.icloud")
					Text("Restore")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
				Spacer()
				Button {
					status = KeychainHelper.standard.delete(key: keychainKey) == errSecSuccess ? .deleted : .deleteFailed
				} label: {
					Image(systemName: "trash")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
				.accessibilityLabel(String(localized: "Delete key backup",
										   comment: "VoiceOver label for the delete key backup button"))
			}
			if let status {
				Text("\(status.description)")
					.font(.caption)
					.foregroundColor(status.success ? .green : .red)
			}
			Text("Backup your private key to your iCloud keychain.")
				.foregroundStyle(.secondary)
				.font(.caption)
		}
	}
}

/// The three admin key slots, over one repeated field. The schema cannot say that a
/// three-slot editor sits on a repeated field, so the whole array is one control.
private struct AdminKeyRows: View {
	@Binding var config: Config.SecurityConfig
	@State private var text: [String] = Array(repeating: "", count: SecurityKey.slots)
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	private static let metadata = FieldMetadataRegistry.get("meshtastic.Config.SecurityConfig", tag: 3)

	private static let titles = [
		String(localized: "Primary Admin Key", comment: "Security setting"),
		String(localized: "Secondary Admin Key", comment: "Security setting"),
		String(localized: "Tertiary Admin Key", comment: "Security setting")
	]

	var body: some View {
		keyRows
			.onAppear { sync() }
			.onChange(of: config.adminKey) { _, _ in sync() }
	}

	@ViewBuilder
	private var keyRows: some View {
		ForEach(0..<SecurityKey.slots, id: \.self) { slot in
			VStack(alignment: .leading) {
				Label(Self.titles[slot], systemImage: "key.viewfinder")
				SecureInput(Self.titles[slot],
							text: binding(for: slot),
							isValid: .constant(SecurityKey.isValid(text[slot])))
					.background(
						RoundedRectangle(cornerRadius: 10.0)
							.stroke(SecurityKey.isValid(text[slot]) ? Color.clear : Color.red, lineWidth: 2.0))
			}
		}
		if let description = Self.metadata?.description {
			Text(description)
				.foregroundStyle(.secondary)
				.font(idiom == .phone ? .caption : .callout)
		}
	}

	/// The radio's keys land after the rows are on screen, so they have to follow them.
	/// Seeding only on appear left the slots empty, and hanging that off the description
	/// meant it would not have run at all for a message with no description.
	private func sync() {
		let incoming = SecurityKey.padded(config.adminKey).map(SecurityKey.text)
		for slot in 0..<SecurityKey.slots where incoming[slot] != text[slot]
			&& SecurityKey.data(text[slot]) != SecurityKey.padded(config.adminKey)[slot] {
			text[slot] = incoming[slot]
		}
	}

	private func binding(for slot: Int) -> Binding<String> {
		Binding(
			get: { text[slot] },
			set: { new in
				text[slot] = new
				// Positional: an empty slot still occupies its place, or the keys after
				// it would shift and authorise the wrong administrator.
				var keys = SecurityKey.padded(config.adminKey)
				keys[slot] = SecurityKey.data(new)
				config.adminKey = keys
			})
	}
}

/// Managed mode locks the user out of their own settings, so it needs an administrator
/// to exist first. Enabling it with no admin key set strands the node.
private struct ManagedDeviceRow: View {
	@Binding var config: Config.SecurityConfig

	private static let metadata = FieldMetadataRegistry.get("meshtastic.Config.SecurityConfig", tag: 4)

	private var hasAdminKey: Bool { config.adminKey.contains { !$0.isEmpty } }

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Toggle(isOn: $config.isManaged) {
				Label(Self.metadata?.label ?? "Managed Device",
					  systemImage: "gearshape.arrow.triangle.2.circlepath")
			}
			.disabled(!hasAdminKey)
			if let description = Self.metadata?.description {
				Text(description)
					.foregroundColor(.gray)
					.font(.callout)
			}
			if !hasAdminKey {
				Label("An admin key must be set before enabling managed mode.",
					  systemImage: "exclamationmark.triangle.fill")
					.font(.caption)
					.foregroundStyle(.orange)
			}
		}
	}
}
