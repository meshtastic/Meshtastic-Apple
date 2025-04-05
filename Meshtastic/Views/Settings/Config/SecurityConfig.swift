//
//  Security.swift
//  Meshtastic
//
// Copyright(c) Garth Vander Houwen 8/7/24.
//

import Foundation
import SwiftUI
import CoreData
import MeshtasticProtobufs
import OSLog

struct SecurityConfig: View {

	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

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
	@State var adminChannelEnabled = false

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Security", config: \.securityConfig, node: node, onAppear: setSecurityValues)
				Text("Security Config Settings require a firmware version 2.5+")
					.font(.title3)
				Section(header: Text("Admin & Direct Message Keys")) {
					VStack(alignment: .leading) {
						Label("Public Key", systemImage: "key")
						Text(publicKey)
							.font(idiom == .phone ? .caption : .callout)
							.allowsTightening(true)
							.monospaced()
							.keyboardType(.alphabet)
							.foregroundStyle(.tertiary)
							.disableAutocorrection(true)
							.textSelection(.enabled)
						Text("Sent out to other nodes on the mesh to allow them to compute a shared secret key.")
							.foregroundStyle(.secondary)
							.font(idiom == .phone ? .caption : .callout)
						Divider()
						Label("Private Key", systemImage: "key.fill")
						SecureInput("Private Key", text: $privateKey, isValid: $hasValidPrivateKey)
							.background(
								RoundedRectangle(cornerRadius: 10.0)
									.stroke(hasValidPrivateKey ? Color.clear : Color.red, lineWidth: 2.0)
							)
						Text("Used to create a shared key with a remote device.")
							.foregroundStyle(.secondary)
							.font(idiom == .phone ? .caption : .callout)
						Divider()
						Label("Primary Admin Key", systemImage: "key.viewfinder")
						SecureInput("Primary Admin Key", text: $adminKey, isValid: $hasValidAdminKey)
							.background(
								RoundedRectangle(cornerRadius: 10.0)
									.stroke(hasValidAdminKey ? Color.clear : Color.red, lineWidth: 2.0)
							)
						Text("The primary public key authorized to send admin messages to this node.")
							.foregroundStyle(.secondary)
							.font(idiom == .phone ? .caption : .callout)
						Divider()
						Label("Secondary Admin Key", systemImage: "key.viewfinder")
						SecureInput("Secondary Admin Key", text: $adminKey2, isValid: $hasValidAdminKey2)
							.background(
								RoundedRectangle(cornerRadius: 10.0)
									.stroke(hasValidAdminKey2 ? Color.clear : Color.red, lineWidth: 2.0)
							)
						Text("The secondary public key authorized to send admin messages to this node.")
							.foregroundStyle(.secondary)
							.font(idiom == .phone ? .caption : .callout)
						Divider()
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
				}
				Section(header: Text("Logs")) {
					Toggle(isOn: $serialEnabled) {
						Label("Serial Console", systemImage: "terminal")
						Text("Serial Console over the Stream API.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $debugLogApiEnabled) {
						Label("Debug Logs", systemImage: "ant.fill")
						Text("Output live debug logging over serial, view and export position-redacted device logs over Bluetooth.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
				Section(header: Text("Administration")) {
					if adminKey.length > 0 || adminChannelEnabled {
						Toggle(isOn: $isManaged) {
							Label("Managed Device", systemImage: "gearshape.arrow.triangle.2.circlepath")
							Text("Device is managed by a mesh administrator, the user is unable to access any of the device settings.")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
					Toggle(isOn: $adminChannelEnabled) {
						Label("Legacy Administration", systemImage: "lock.slash")
						Text("Allow incoming device control over the insecure legacy admin channel.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
			}
		}
		.scrollDismissesKeyboard(.immediately)
		.navigationTitle("Security Config")
		.navigationBarItems(trailing: ZStack {
			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: "\(bleManager.connectedPeripheral?.shortName ?? "?")"
			)
		})
		.onChange(of: isManaged) { _, newIsManaged in
			if newIsManaged != node?.securityConfig?.isManaged { hasChanges = true }
		}
		.onChange(of: serialEnabled) { _, newSerialEnabled in
			if newSerialEnabled != node?.securityConfig?.serialEnabled { hasChanges = true }
		}
		.onChange(of: debugLogApiEnabled) { _, newDebugLogApiEnabled in
			if newDebugLogApiEnabled != node?.securityConfig?.debugLogApiEnabled { hasChanges = true }
		}
		.onChange(of: adminChannelEnabled) { _, newAdminChannelEnabled in
			if newAdminChannelEnabled != node?.securityConfig?.adminChannelEnabled { hasChanges = true }
		}
		.onChange(of: privateKey) {
			let tempKey = Data(base64Encoded: privateKey) ?? Data()
			if tempKey.count == 32 {
				hasValidPrivateKey = true
			} else {
				hasValidPrivateKey = false
			}
			hasChanges = true
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
			hasChanges = true
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
			hasChanges = true
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
			hasChanges = true
		}
		.onFirstAppear {
			// Need to request a DeviceConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.securityConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired security config requesting via PKI admin")
								_ = bleManager.requestSecurityConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							if node.deviceConfig == nil {
								/// Legacy Administration
								Logger.mesh.info("☠️ Using insecure legacy admin, empty security config")
								_ = bleManager.requestSecurityConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						}
					}
				}
			}
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {

			if !hasValidPrivateKey || !hasValidAdminKey || !hasValidAdminKey2 || !hasValidAdminKey3 {
				return
			}

			guard let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context),
				  let fromUser = connectedNode.user,
				  let toUser = node?.user else {
				return
			}

			var config = Config.SecurityConfig()
			config.publicKey = Data(base64Encoded: publicKey) ?? Data()
			config.privateKey = Data(base64Encoded: privateKey) ?? Data()
			config.adminKey = [Data(base64Encoded: adminKey) ?? Data(), Data(base64Encoded: adminKey2) ?? Data(), Data(base64Encoded: adminKey3) ?? Data()]
			config.isManaged = isManaged
			config.serialEnabled = serialEnabled
			config.debugLogApiEnabled = debugLogApiEnabled
			config.adminChannelEnabled = adminChannelEnabled

			let adminMessageId = bleManager.saveSecurityConfig(
				config: config,
				fromUser: fromUser,
				toUser: toUser,
				adminIndex: connectedNode.myInfo?.adminIndex ?? 0
			)
			if adminMessageId > 0 {
				// Should show a saved successfully alert once I know that to be true
				// for now just disable the button after a successful save
				hasChanges = false
				goBack()
			}
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
		self.adminChannelEnabled = node?.securityConfig?.adminChannelEnabled ?? false
		self.hasChanges = false
	}
}
