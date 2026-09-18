//
//  TrafficManagementConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import SwiftData
import OSLog
import MeshtasticProtobufs

extension ModuleConfig.TrafficManagementConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, TrafficManagementConfigEntity?> = \NodeInfoEntity.trafficManagementConfig

	init(entity: TrafficManagementConfigEntity) {
		self.init()
		positionMinIntervalSecs = UInt32(truncatingIfNeeded: entity.positionMinIntervalSecs)
		nodeinfoDirectResponseMaxHops = UInt32(truncatingIfNeeded: entity.nodeinfoDirectResponseMaxHops)
		rateLimitWindowSecs = UInt32(truncatingIfNeeded: entity.rateLimitWindowSecs)
		rateLimitMaxPackets = UInt32(truncatingIfNeeded: entity.rateLimitMaxPackets)
		unknownPacketThreshold = UInt32(truncatingIfNeeded: entity.unknownPacketThreshold)
	}
}

/// The 2.8 schema has no on/off flags: a feature is on when its value is non-zero. Each
/// value is a non-zero toggle here, and the main switch below is the app's own.
struct TrafficManagementConfig: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	/// The main switch is not a field. This holds it on while every value is still
	/// zero, so the feature sections show and can be filled in.
	@State private var switchedOn = false
	@State private var directNeighborCount = 0

	private typealias F = ModuleConfig.TrafficManagementConfig.Fields

	/// On when any feature has a value.
	static func isActive(_ config: ModuleConfig.TrafficManagementConfig) -> Bool {
		config.positionMinIntervalSecs != 0 || config.nodeinfoDirectResponseMaxHops != 0
			|| config.rateLimitWindowSecs != 0 || config.rateLimitMaxPackets != 0 || config.unknownPacketThreshold != 0
	}

	/// Switching the main switch off clears every feature.
	static func cleared(_ config: ModuleConfig.TrafficManagementConfig) -> ModuleConfig.TrafficManagementConfig {
		var c = config
		c.positionMinIntervalSecs = 0
		c.nodeinfoDirectResponseMaxHops = 0
		c.rateLimitWindowSecs = 0
		c.rateLimitMaxPackets = 0
		c.unknownPacketThreshold = 0
		return c
	}

	/// The rate limit is one feature in two fields; a cleared window takes the count with it.
	static func reconcile(_ config: inout ModuleConfig.TrafficManagementConfig) {
		if config.rateLimitWindowSecs == 0 { config.rateLimitMaxPackets = 0 }
	}

	static func overlay(switchedOn: Bool = false) -> ConfigFormOverlay<ModuleConfig.TrafficManagementConfig> {
		typealias Condition = ConfigFormCondition<ModuleConfig.TrafficManagementConfig>
		let on = Condition.any([
			.environment { _ in switchedOn },
			.nonZero(F.positionMinIntervalSecs), .nonZero(F.nodeinfoDirectResponseMaxHops),
			.nonZero(F.rateLimitWindowSecs), .nonZero(F.rateLimitMaxPackets), .nonZero(F.unknownPacketThreshold)
		])
		return .init(sections: [
			.init(title: String(localized: "Position Deduplication", comment: "Settings section"), shownWhen: on, fields: [
				// Five hours between identical positions is the firmware default.
				.init(F.positionMinIntervalSecs, symbol: "location.slash",
					  control: .nonZeroToggle(onValue: 18000, then: .interval(.trafficPositionDedup)))
			]),
			.init(title: String(localized: "NodeInfo Direct Response", comment: "Settings section"), shownWhen: on, fields: [
				// Firmware clamps to a role limit of 3 hops, so offering more would be silently ignored.
				.init(F.nodeinfoDirectResponseMaxHops, symbol: "arrow.turn.down.right",
					  control: .nonZeroToggle(onValue: 1, then: .options((1...3).map { ConfigFormOption(value: $0, title: "\($0)") })))
			]),
			.init(title: String(localized: "Rate Limiting", comment: "Settings section"), shownWhen: on, fields: [
				// One minute is the shortest broadly useful window.
				.init(F.rateLimitWindowSecs, symbol: "speedometer",
					  control: .nonZeroToggle(onValue: 60, then: .interval(.trafficRateLimitWindow))),
				.init(F.rateLimitMaxPackets, symbol: "number", shownWhen: .nonZero(F.rateLimitWindowSecs))
			]),
			.init(title: String(localized: "Unknown Packet Handling", comment: "Settings section"), shownWhen: on, fields: [
				// The old screen switched this on at zero, which saved as off; start at ten per window.
				.init(F.unknownPacketThreshold, symbol: "xmark.shield", control: .nonZeroToggle(onValue: 10))
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Traffic Management", overlay: Self.overlay(switchedOn: switchedOn),
			reconcile: { config, _ in Self.reconcile(&config) },
			request: accessoryManager.requestTrafficManagementModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveTrafficManagementModuleConfig(config: config, fromUser: from, toUser: to)
			},
			leading: { config in
				Section(header: Text("Placement")) {
					Label {
						Text(TrafficManagementCandidacy.summary(directNeighborCount: directNeighborCount))
							.font(.callout)
							.fixedSize(horizontal: false, vertical: true)
					} icon: {
						Image(systemName: "antenna.radiowaves.left.and.right")
							.foregroundStyle(
								TrafficManagementCandidacy.tier(directNeighborCount: directNeighborCount) == .limited
								? Color.orange : Color.green
							)
					}
				}
				Section(header: Text("Options")) {
					Toggle(isOn: Binding(
						get: { switchedOn || Self.isActive(config.wrappedValue) },
						set: { on in
							switchedOn = on
							if !on { config.wrappedValue = Self.cleared(config.wrappedValue) }
						}
					)) {
						Label("Enabled", systemImage: "arrow.triangle.branch")
					}
				}
			})
		.navigationTitle("Traffic Management Config")
		.onAppear(perform: refreshDirectNeighborCount)
	}

	/// Nodes this radio has heard directly and recently: zero hops, over RF, inside the same
	/// two-hour window the node filters treat as online. Both dates are bound to locals: the
	/// #Predicate macro rejects constructors and self-reaching expressions inside the closure,
	/// and the failure would otherwise be a silent zero.
	private func refreshDirectNeighborCount() {
		let cutoff = Date().addingTimeInterval(-7_200)
		let epoch = Date(timeIntervalSince1970: 0)
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.hopsAway == 0 && $0.viaMqtt == false && ($0.lastHeard ?? epoch) > cutoff }
		)
		do {
			directNeighborCount = try context.fetchCount(descriptor)
		} catch {
			Logger.data.error("Could not count direct neighbors for the traffic management screen: \(error.localizedDescription, privacy: .public)")
			directNeighborCount = 0
		}
	}
}
