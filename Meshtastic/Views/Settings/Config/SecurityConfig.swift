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
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
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
