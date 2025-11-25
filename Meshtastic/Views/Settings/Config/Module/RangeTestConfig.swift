//
//  RangeTestConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import MeshtasticProtobufs
import CoreData
import OSLog
import SwiftUI

struct RangeTestConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var enabled = false
	@State var save = false
	@State private var sender: UpdateInterval = UpdateInterval(from: 0)
	private var isPrimaryChannelPublic: Bool {
		guard let channels = node?.myInfo?.channels?.array as? [ChannelEntity] else {
			return false
		}
		// Treat the primary channel on this node as "public" when it is effectively unencrypted
		// or using a minimal 1-byte key (hexDescription shorter than 3 characters).
		guard let primary = channels.first(where: { $0.index == 0 && $0.role > 0 }) else {
			return false
		}
		let hexLen = primary.psk?.hexDescription.count ?? 0
		return hexLen < 3
	}

	
	var body: some View {
		Form {
			ConfigHeader(title: "Range", config: \.rangeTestConfig, node: node, onAppear: setRangeTestValues)
			
			Section(header: Text("Options")) {
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "figure.walk")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				.listRowSeparator(.visible)
				UpdateIntervalPicker(
					config: .rangeTestSender,
					pickerLabel: "Sender Interval",
					selectedInterval: $sender
				)
				.listRowSeparator(.hidden)
				Text("This device will send out range test messages on the selected interval.")
					.foregroundColor(.gray)
					.font(.callout)
				
				Toggle(isOn: $save) {
					Label("Save", systemImage: "square.and.arrow.down.fill")
					Text("Saves a CSV with the range test message details, currently only available on ESP32 devices with a web server.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				.disabled(!(node != nil && node?.metadata?.hasWifi ?? false))
				
			}
		}
		.disabled(!accessoryManager.isConnected || node?.rangeTestConfig == nil || isPrimaryChannelPublic)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context)
					if connectedNode != nil {
						var rtc = ModuleConfig.RangeTestConfig()
						let effectiveEnabled = isPrimaryChannelPublic ? false : enabled
						rtc.enabled = effectiveEnabled
						rtc.save = save
						rtc.sender = UInt32(sender.intValue)
						Task {
							_ = try await accessoryManager.saveRangeTestModuleConfig(config: rtc, fromUser: connectedNode!.user!, toUser: node!.user!)
							Task { @MainActor in
								// Should show a saved successfully alert once I know that to be true
								// for now just disable the button after a successful save
								hasChanges = false
								goBack()
							}
						}
					}
				}}}
		.navigationTitle("Range Test Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					deviceConnected: accessoryManager.isConnected,
					name: accessoryManager.activeConnection?.device.shortName ?? "?"
				)
			}
		)
		.onFirstAppear {
			// Need to request a RangeTestModuleConfig from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.rangeTestConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired range test module config requesting via PKI admin")
										try await accessoryManager.requestRangeTestModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.error("🚨 Request Range test module config failed")
									}
								}
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
						}
					}
				}
			}
		}
		.onChange(of: enabled) { _, newEnabled in
			if newEnabled != node?.rangeTestConfig?.enabled { hasChanges = true }
		}
		.onChange(of: save) { _, newSave in
			if newSave != node?.rangeTestConfig?.save { hasChanges = true }
		}
		.onChange(of: sender.intValue) { _, newSender in
			if newSender != node?.rangeTestConfig?.sender ?? -1 { hasChanges = true }
		}
		
	}
	func setRangeTestValues() {
		self.enabled = node?.rangeTestConfig?.enabled ?? false
		self.save = node?.rangeTestConfig?.save ?? false
		self.sender = UpdateInterval(from: Int(node?.rangeTestConfig?.sender ?? 0))
		self.hasChanges = false
	}
}
