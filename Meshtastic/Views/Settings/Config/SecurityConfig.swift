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

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State var hasChanges = false
	@State var publicKey = ""
	@State var privateKey = ""
	@State var adminKey = ""
	@State var isManaged = false
	@State var serialEnabled = false
	@State var debugLogApiEnabled = false
	@State var bluetoothLoggingEnabled = false
	@State var adminChannelEnabled = false

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Security", config: \.securityConfig, node: node, onAppear: setSecurityValues)

				Section(header: Text("Admin & Direct Message Keys")) {
					VStack(alignment: .leading) {
						Label("Public Key", systemImage: "key")

						Text("Sent out to other nodes on the mesh to allow them to compute a shared secret key.")
							.foregroundStyle(.secondary)
							.font(.caption)

						TextField(
							"Public Key",
							text: $publicKey,
							axis: .vertical
						)
						.padding(5)
						.keyboardType(.alphabet)
						.foregroundColor(.secondary)
						.disableAutocorrection(true)
						.textSelection(.enabled)
						.background(
							RoundedRectangle(cornerRadius: 10.0)
								.stroke(true ? Color.clear : Color.red, lineWidth: 2.0)
						)

					}
					VStack(alignment: .leading) {
						Label("Private Key", systemImage: "key.fill")

						Text("Used to create a shared key with a remote device.")
							.foregroundStyle(.secondary)
							.font(.caption)

						TextField(
							"Private Key",
							text: $privateKey,
							axis: .vertical
						)
						.padding(5)
						.disableAutocorrection(true)
						.keyboardType(.alphabet)
						.foregroundColor(.secondary)
						.textSelection(.enabled)
						.background(
							RoundedRectangle(cornerRadius: 10.0)
								.stroke(true ? Color.clear : Color.red, lineWidth: 2.0)
						)
					}
					VStack(alignment: .leading) {
						Label("Admin Key", systemImage: "key.viewfinder")

						Text("The public key authorized to send admin messages to this node.")
							.foregroundStyle(.secondary)
							.font(.caption)

						TextField(
							"Admin Key",
							text: $adminKey,
							axis: .vertical
						)
						.padding(5)
						.disableAutocorrection(true)
						.keyboardType(.alphabet)
						.foregroundColor(.secondary)
						.textSelection(.enabled)
						.background(
							RoundedRectangle(cornerRadius: 10.0)
								.stroke(true ? Color.clear : Color.red, lineWidth: 2.0)
						)
					}
				}
				Section(header: Text("Logs")) {
					Toggle(isOn: $bluetoothLoggingEnabled) {
						Label("Bluetooth Logs", systemImage: "dot.radiowaves.right")
						Text("View and export position-redacted device logs over Bluetooth")
						Link("View Logs", destination: URL(string: "meshtastic:///settings/debugLogs")!)
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
				Section(header: Text("Administration")) {
					if adminKey.length > 0 || adminChannelEnabled {
						Toggle(isOn: $isManaged) {
							Label("Managed Device", systemImage: "gearshape.arrow.triangle.2.circlepath")
							Text("Device is managed by a mesh administrator.")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
					Toggle(isOn: $adminChannelEnabled) {
						Label("Legacy Administration", systemImage: "lock.slash")
						Text("Allow incoming device control over the insecure legacy admin channel.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
				Section(header: Text("Developer")) {
					Toggle(isOn: $serialEnabled) {
						Label("Serial Console", systemImage: "terminal")
						Text("Serial Console over the Stream API.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if serialEnabled {
						Toggle(isOn: $debugLogApiEnabled) {
							Label("Serial Debug Logs", systemImage: "ant.fill")
							Text("Output live debug logging over serial.")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					}
				}
			}
		}
		.navigationTitle("Security Config")
		.navigationBarItems(trailing: ZStack {
			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: "\(bleManager.connectedPeripheral?.shortName ?? "?")"
			)
		})
		.onChange(of: isManaged) { newIsManaged in
			if node != nil && node!.securityConfig != nil {
				if newIsManaged != node!.securityConfig!.isManaged { hasChanges = true }
			}
		}
		.onChange(of: serialEnabled) { newSerialEnabled in
			if node != nil && node!.securityConfig != nil {
				if newSerialEnabled != node!.securityConfig!.serialEnabled { hasChanges = true }
			}
		}
		.onChange(of: debugLogApiEnabled) { newDebugLogApiEnabled in
			if node != nil && node!.securityConfig != nil {
				if newDebugLogApiEnabled != node!.securityConfig!.debugLogApiEnabled { hasChanges = true }
			}
		}
		.onChange(of: bluetoothLoggingEnabled) { newBluetoothLoggingEnabled in
			if node != nil && node!.securityConfig != nil {
				if newBluetoothLoggingEnabled != node!.securityConfig!.bluetoothLoggingEnabled { hasChanges = true }
			}
		}
		.onChange(of: adminChannelEnabled) { newAdminChannelEnabled in
			if node != nil && node!.securityConfig != nil {
				if newAdminChannelEnabled != node!.securityConfig!.adminChannelEnabled { hasChanges = true }
			}
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			guard let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context),
				  let fromUser = connectedNode.user,
				  let toUser = node?.user else {
				return
			}

			var config = Config.SecurityConfig()
			//config.publicKey = publicKey
			//config.privateKey = privateKey
			//config.adminKey = adminKey
			config.isManaged = isManaged
			config.serialEnabled = serialEnabled
			config.debugLogApiEnabled = debugLogApiEnabled
			config.bluetoothLoggingEnabled = bluetoothLoggingEnabled
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
		self.adminKey = node?.securityConfig?.adminKey?.base64EncodedString() ?? ""
		self.isManaged = node?.securityConfig?.isManaged ?? false
		self.serialEnabled = node?.securityConfig?.serialEnabled ?? false
		self.debugLogApiEnabled = node?.securityConfig?.debugLogApiEnabled ?? false
		self.bluetoothLoggingEnabled = node?.securityConfig?.bluetoothLoggingEnabled ?? false
		self.adminChannelEnabled = node?.securityConfig?.adminChannelEnabled ?? false
		self.hasChanges = false
	}
}
