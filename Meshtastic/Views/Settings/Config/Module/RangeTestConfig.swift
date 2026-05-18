//
//  RangeTestConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import MeshtasticProtobufs
import SwiftData
import OSLog
import SwiftUI

struct RangeTestConfig: View {
	
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	let node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var enabled = false
	@State var save = false
	@State private var sender: UpdateInterval = UpdateInterval(from: 0)
	private var isPrimaryChannelPublic: Bool {
		guard let channels = node?.myInfo?.channels else {
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

			if isPrimaryChannelPublic {
				Section {
					Label("Range test requires an encrypted private channel. The primary channel on this node is using a default or empty key.", systemImage: "lock.open.fill")
						.font(.callout)
						.foregroundColor(.orange)
				}
			} else if accessoryManager.isConnected && node != nil && node?.rangeTestConfig == nil {
				Section {
					Label("Range test configuration has not been received from the radio. Try reconnecting to the device.", systemImage: "exclamationmark.triangle.fill")
						.font(.callout)
						.foregroundColor(.orange)
				}
			}

			Section(header: Text("Options")) {
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "figure.walk")
				}
				.tint(.accentColor)
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
				.tint(.accentColor)
				.disabled(!(node != nil && node?.metadata?.hasWifi ?? false))
				
			}
		}
		.disabled(!accessoryManager.isConnected || node?.rangeTestConfig == nil || isPrimaryChannelPublic)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				performConfigSave(
					node: node,
					context: context,
					accessoryManager: accessoryManager,
					hasChanges: $hasChanges,
					dismiss: goBack
				) { fromUser, toUser in
					var rtc = ModuleConfig.RangeTestConfig()
					let effectiveEnabled = isPrimaryChannelPublic ? false : enabled
					rtc.enabled = effectiveEnabled
					rtc.save = save
					rtc.sender = UInt32(sender.intValue)
					_ = try await accessoryManager.saveRangeTestModuleConfig(config: rtc, fromUser: fromUser, toUser: toUser)
				}
			}}}
		.navigationTitle("Range Test Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.rangeTestConfig == nil },
				request: accessoryManager.requestRangeTestModuleConfig,
				requestForConnectedNode: true
			)
		}
		.onChange(of: enabled) { _, newEnabled in
			if newEnabled != node?.rangeTestConfig?.enabled { hasChanges = true }

			// Note: even if this is the connected node, we don't have to update AccessoryManager.wantRangeTestPackets here, because the node will reboot after we save config changes, and we'll pick up the new value after we reconnect.
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

#Preview {
	RangeTestConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
