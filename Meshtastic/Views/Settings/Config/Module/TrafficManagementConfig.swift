//
//  TrafficManagementConfig.swift
//  Meshtastic
//

import MeshtasticProtobufs
import OSLog
import SwiftUI

struct TrafficManagementConfig: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack

	let node: NodeInfoEntity?

	// The 2.8 firmware schema dropped the per-feature boolean flags and the
	// precision-bits / hop-management fields. Each feature is now enabled
	// implicitly by a non-zero value, so the toggles below are UI-only: they
	// gate whether the corresponding interval/threshold is sent (a value) or
	// cleared (0). `enabled` is a master switch that clears everything when off.
	@State var hasChanges = false
	@State var enabled = false
	@State var positionDedupEnabled = false
	@State var positionMinIntervalSecs = 0
	@State var nodeinfoDirectResponse = false
	@State var nodeinfoDirectResponseMaxHops = 0
	@State var rateLimitEnabled = false
	@State var rateLimitWindowSecs = 0
	@State var rateLimitMaxPackets = 0
	@State var dropUnknownEnabled = false
	@State var unknownPacketThreshold = 0

	var body: some View {
		Form {
			ConfigHeader(title: "Traffic Management", config: \.trafficManagementConfig, node: node, onAppear: setTrafficManagementValues)

			Section(header: Text("Options")) {
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "arrow.triangle.branch")
					Text("Master enable for the traffic management module.")
				}
				.tint(.accentColor)
			}

			if enabled {
				Section(header: Text("Position Deduplication")) {
					Toggle(isOn: $positionDedupEnabled) {
						Label("Position Dedup", systemImage: "location.slash")
						Text("Drop redundant position broadcasts from the same node.")
					}
					.tint(.accentColor)

					if positionDedupEnabled {
						HStack {
							Label("Min Interval (s)", systemImage: "clock")
							Spacer()
							TextField("Seconds", value: $positionMinIntervalSecs, format: .number)
								.frame(width: 80)
								.textFieldStyle(.roundedBorder)
								.keyboardType(.numberPad)
						}
						Text("Minimum interval in seconds between position updates from the same node.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}

				Section(header: Text("NodeInfo Direct Response")) {
					Toggle(isOn: $nodeinfoDirectResponse) {
						Label("Direct Response", systemImage: "arrow.turn.down.right")
						Text("Respond to NodeInfo requests directly from local cache.")
					}
					.tint(.accentColor)

					if nodeinfoDirectResponse {
						HStack {
							Label("Max Hops", systemImage: "point.3.connected.trianglepath.dotted")
							Spacer()
							TextField("Hops", value: $nodeinfoDirectResponseMaxHops, format: .number)
								.frame(width: 80)
								.textFieldStyle(.roundedBorder)
								.keyboardType(.numberPad)
						}
						Text("Maximum hop distance from the requestor at which direct NodeInfo responses are served from the local cache.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}

				Section(header: Text("Rate Limiting")) {
					Toggle(isOn: $rateLimitEnabled) {
						Label("Rate Limiting", systemImage: "speedometer")
						Text("Enable per-node rate limiting to throttle chatty nodes.")
					}
					.tint(.accentColor)

					if rateLimitEnabled {
						HStack {
							Label("Window (s)", systemImage: "clock.arrow.circlepath")
							Spacer()
							TextField("Seconds", value: $rateLimitWindowSecs, format: .number)
								.frame(width: 80)
								.textFieldStyle(.roundedBorder)
								.keyboardType(.numberPad)
						}
						Text("Time window in seconds for rate limiting calculations.")
							.foregroundColor(.gray)
							.font(.callout)

						HStack {
							Label("Max Packets", systemImage: "number")
							Spacer()
							TextField("Packets", value: $rateLimitMaxPackets, format: .number)
								.frame(width: 80)
								.textFieldStyle(.roundedBorder)
								.keyboardType(.numberPad)
						}
						Text("Maximum packets allowed per node within the rate limit window.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}

				Section(header: Text("Unknown Packet Handling")) {
					Toggle(isOn: $dropUnknownEnabled) {
						Label("Drop Unknown", systemImage: "xmark.shield")
						Text("Enable dropping of unknown/undecryptable packets.")
					}
					.tint(.accentColor)

					if dropUnknownEnabled {
						HStack {
							Label("Threshold", systemImage: "number.square")
							Spacer()
							TextField("Count", value: $unknownPacketThreshold, format: .number)
								.frame(width: 80)
								.textFieldStyle(.roundedBorder)
								.keyboardType(.numberPad)
						}
						Text("Maximum unknown/undecryptable packets per rate window before the source is dropped.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}
			}
		}
		.scrollDismissesKeyboard(.immediately)
		.disabled(!accessoryManager.isConnected || node?.trafficManagementConfig == nil)
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
					// 2.8 schema: each feature is enabled by a non-zero value, so
					// a disabled toggle (or the master switch off) sends 0.
					var tmc = ModuleConfig.TrafficManagementConfig()
					tmc.positionMinIntervalSecs = UInt32(enabled && positionDedupEnabled ? positionMinIntervalSecs : 0)
					tmc.nodeinfoDirectResponseMaxHops = UInt32(enabled && nodeinfoDirectResponse ? nodeinfoDirectResponseMaxHops : 0)
					tmc.rateLimitWindowSecs = UInt32(enabled && rateLimitEnabled ? rateLimitWindowSecs : 0)
					tmc.rateLimitMaxPackets = UInt32(enabled && rateLimitEnabled ? rateLimitMaxPackets : 0)
					tmc.unknownPacketThreshold = UInt32(enabled && dropUnknownEnabled ? unknownPacketThreshold : 0)
					_ = try await accessoryManager.saveTrafficManagementModuleConfig(config: tmc, fromUser: fromUser, toUser: toUser)
				}
			}
			}
		}
		.navigationTitle("Traffic Management Config")
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
				configIsNil: { $0.trafficManagementConfig == nil },
				request: accessoryManager.requestTrafficManagementModuleConfig
			)
		}
		.onChange(of: enabled) { oldVal, newVal in
			if oldVal != newVal && newVal != node?.trafficManagementConfig?.enabled { hasChanges = true }
		}
		.onChange(of: positionDedupEnabled) { oldVal, newVal in
			if oldVal != newVal && newVal != node?.trafficManagementConfig?.positionDedupEnabled { hasChanges = true }
		}
		.onChange(of: positionMinIntervalSecs) { oldVal, newVal in
			if oldVal != newVal && newVal != Int(node?.trafficManagementConfig?.positionMinIntervalSecs ?? -1) { hasChanges = true }
		}
		.onChange(of: nodeinfoDirectResponse) { oldVal, newVal in
			if oldVal != newVal && newVal != node?.trafficManagementConfig?.nodeinfoDirectResponse { hasChanges = true }
		}
		.onChange(of: nodeinfoDirectResponseMaxHops) { oldVal, newVal in
			if oldVal != newVal && newVal != Int(node?.trafficManagementConfig?.nodeinfoDirectResponseMaxHops ?? -1) { hasChanges = true }
		}
		.onChange(of: rateLimitEnabled) { oldVal, newVal in
			if oldVal != newVal && newVal != node?.trafficManagementConfig?.rateLimitEnabled { hasChanges = true }
		}
		.onChange(of: rateLimitWindowSecs) { oldVal, newVal in
			if oldVal != newVal && newVal != Int(node?.trafficManagementConfig?.rateLimitWindowSecs ?? -1) { hasChanges = true }
		}
		.onChange(of: rateLimitMaxPackets) { oldVal, newVal in
			if oldVal != newVal && newVal != Int(node?.trafficManagementConfig?.rateLimitMaxPackets ?? -1) { hasChanges = true }
		}
		.onChange(of: dropUnknownEnabled) { oldVal, newVal in
			if oldVal != newVal && newVal != node?.trafficManagementConfig?.dropUnknownEnabled { hasChanges = true }
		}
		.onChange(of: unknownPacketThreshold) { oldVal, newVal in
			if oldVal != newVal && newVal != Int(node?.trafficManagementConfig?.unknownPacketThreshold ?? -1) { hasChanges = true }
		}
	}

	func setTrafficManagementValues() {
		// Derive the UI toggles from the stored values: a non-zero interval /
		// threshold means that feature is active (mirrors the firmware schema).
		let cfg = node?.trafficManagementConfig
		self.positionMinIntervalSecs = Int(cfg?.positionMinIntervalSecs ?? 0)
		self.nodeinfoDirectResponseMaxHops = Int(cfg?.nodeinfoDirectResponseMaxHops ?? 0)
		self.rateLimitWindowSecs = Int(cfg?.rateLimitWindowSecs ?? 0)
		self.rateLimitMaxPackets = Int(cfg?.rateLimitMaxPackets ?? 0)
		self.unknownPacketThreshold = Int(cfg?.unknownPacketThreshold ?? 0)

		self.positionDedupEnabled = self.positionMinIntervalSecs > 0
		self.nodeinfoDirectResponse = self.nodeinfoDirectResponseMaxHops > 0
		self.rateLimitEnabled = self.rateLimitWindowSecs > 0 || self.rateLimitMaxPackets > 0
		self.dropUnknownEnabled = self.unknownPacketThreshold > 0
		self.enabled = self.positionDedupEnabled || self.nodeinfoDirectResponse || self.rateLimitEnabled || self.dropUnknownEnabled
		self.hasChanges = false
	}
}

#Preview {
	TrafficManagementConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
}
