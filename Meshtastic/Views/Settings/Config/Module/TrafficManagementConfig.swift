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

	@State var hasChanges = false
	@State var enabled = false
	@State var positionDedupEnabled = false
	@State var positionPrecisionBits = 0
	@State var positionMinIntervalSecs = 0
	@State var nodeinfoDirectResponse = false
	@State var nodeinfoDirectResponseMaxHops = 0
	@State var rateLimitEnabled = false
	@State var rateLimitWindowSecs = 0
	@State var rateLimitMaxPackets = 0
	@State var dropUnknownEnabled = false
	@State var unknownPacketThreshold = 0
	@State var exhaustHopTelemetry = false
	@State var exhaustHopPosition = false
	@State var routerPreserveHops = false

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
							Label("Precision Bits", systemImage: "slider.horizontal.3")
							Spacer()
							TextField("Bits", value: $positionPrecisionBits, format: .number)
								.frame(width: 80)
								.textFieldStyle(.roundedBorder)
								.keyboardType(.numberPad)
						}
						Text("Number of bits of precision for position deduplication (0-32).")
							.foregroundColor(.gray)
							.font(.callout)

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
						Text("Minimum hop distance from requestor before responding to NodeInfo requests.")
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
						Text("Number of unknown packets before dropping from a node.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}

				Section(header: Text("Hop Management")) {
					Toggle(isOn: $exhaustHopTelemetry) {
						Label("Exhaust Hop Telemetry", systemImage: "arrow.down.to.line")
						Text("Set hop_limit to 0 for relayed telemetry broadcasts (own packets unaffected).")
					}
					.tint(.accentColor)

					Toggle(isOn: $exhaustHopPosition) {
						Label("Exhaust Hop Position", systemImage: "arrow.down.to.line")
						Text("Set hop_limit to 0 for relayed position broadcasts (own packets unaffected).")
					}
					.tint(.accentColor)

					Toggle(isOn: $routerPreserveHops) {
						Label("Router Preserve Hops", systemImage: "arrow.triangle.2.circlepath")
						Text("Preserve hop_limit for router-to-router traffic.")
					}
					.tint(.accentColor)
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
					var tmc = ModuleConfig.TrafficManagementConfig()
					tmc.enabled = self.enabled
					tmc.positionDedupEnabled = self.positionDedupEnabled
					tmc.positionPrecisionBits = UInt32(self.positionPrecisionBits)
					tmc.positionMinIntervalSecs = UInt32(self.positionMinIntervalSecs)
					tmc.nodeinfoDirectResponse = self.nodeinfoDirectResponse
					tmc.nodeinfoDirectResponseMaxHops = UInt32(self.nodeinfoDirectResponseMaxHops)
					tmc.rateLimitEnabled = self.rateLimitEnabled
					tmc.rateLimitWindowSecs = UInt32(self.rateLimitWindowSecs)
					tmc.rateLimitMaxPackets = UInt32(self.rateLimitMaxPackets)
					tmc.dropUnknownEnabled = self.dropUnknownEnabled
					tmc.unknownPacketThreshold = UInt32(self.unknownPacketThreshold)
					tmc.exhaustHopTelemetry = self.exhaustHopTelemetry
					tmc.exhaustHopPosition = self.exhaustHopPosition
					tmc.routerPreserveHops = self.routerPreserveHops
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
		.onChange(of: positionPrecisionBits) { oldVal, newVal in
			if oldVal != newVal && newVal != Int(node?.trafficManagementConfig?.positionPrecisionBits ?? -1) { hasChanges = true }
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
		.onChange(of: exhaustHopTelemetry) { oldVal, newVal in
			if oldVal != newVal && newVal != node?.trafficManagementConfig?.exhaustHopTelemetry { hasChanges = true }
		}
		.onChange(of: exhaustHopPosition) { oldVal, newVal in
			if oldVal != newVal && newVal != node?.trafficManagementConfig?.exhaustHopPosition { hasChanges = true }
		}
		.onChange(of: routerPreserveHops) { oldVal, newVal in
			if oldVal != newVal && newVal != node?.trafficManagementConfig?.routerPreserveHops { hasChanges = true }
		}
	}

	func setTrafficManagementValues() {
		self.enabled = node?.trafficManagementConfig?.enabled ?? false
		self.positionDedupEnabled = node?.trafficManagementConfig?.positionDedupEnabled ?? false
		self.positionPrecisionBits = Int(node?.trafficManagementConfig?.positionPrecisionBits ?? 0)
		self.positionMinIntervalSecs = Int(node?.trafficManagementConfig?.positionMinIntervalSecs ?? 0)
		self.nodeinfoDirectResponse = node?.trafficManagementConfig?.nodeinfoDirectResponse ?? false
		self.nodeinfoDirectResponseMaxHops = Int(node?.trafficManagementConfig?.nodeinfoDirectResponseMaxHops ?? 0)
		self.rateLimitEnabled = node?.trafficManagementConfig?.rateLimitEnabled ?? false
		self.rateLimitWindowSecs = Int(node?.trafficManagementConfig?.rateLimitWindowSecs ?? 0)
		self.rateLimitMaxPackets = Int(node?.trafficManagementConfig?.rateLimitMaxPackets ?? 0)
		self.dropUnknownEnabled = node?.trafficManagementConfig?.dropUnknownEnabled ?? false
		self.unknownPacketThreshold = Int(node?.trafficManagementConfig?.unknownPacketThreshold ?? 0)
		self.exhaustHopTelemetry = node?.trafficManagementConfig?.exhaustHopTelemetry ?? false
		self.exhaustHopPosition = node?.trafficManagementConfig?.exhaustHopPosition ?? false
		self.routerPreserveHops = node?.trafficManagementConfig?.routerPreserveHops ?? false
		self.hasChanges = false
	}
}

#Preview {
	TrafficManagementConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
}
