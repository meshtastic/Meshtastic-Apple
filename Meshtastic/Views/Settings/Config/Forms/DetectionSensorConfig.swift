//
//  DetectionSensorConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import SwiftUI
import MeshtasticProtobufs

enum DetectionSensorRole: String, CaseIterable, Equatable, Decodable {
	case sensor
	case client

	var description: String {
		switch self {
		case .sensor: return String(localized: "Sensor", comment: "DetectionSensorRole.description")
		case .client: return String(localized: "Client", comment: "DetectionSensorRole.description")
		}
	}
}

extension ModuleConfig.DetectionSensorConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, DetectionSensorConfigEntity?> = \NodeInfoEntity.detectionSensorConfig

	init(entity: DetectionSensorConfigEntity) {
		self.init()
		enabled = entity.enabled
		minimumBroadcastSecs = UInt32(truncatingIfNeeded: entity.minimumBroadcastSecs)
		stateBroadcastSecs = UInt32(truncatingIfNeeded: entity.stateBroadcastSecs)
		sendBell = entity.sendBell
		name = entity.name ?? ""
		monitorPin = UInt32(truncatingIfNeeded: entity.monitorPin)
		detectionTriggerType = TriggerType(rawValue: Int(entity.triggerType)) ?? .logicLow
		usePullup = entity.usePullup
	}
}

struct DetectionSensorConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@AppStorage("detectionSensorRole") private var role: DetectionSensorRole = .sensor
	@AppStorage("enableDetectionNotifications") private var detectionNotificationsEnabled = false
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.DetectionSensorConfig.Fields

	/// The role is an app preference, not a radio setting: it decides which half of the
	/// screen this device needs, and the radio never sees it.
	static func overlay(role: DetectionSensorRole = .sensor) -> ConfigFormOverlay<ModuleConfig.DetectionSensorConfig> {
		let enabled = ConfigFormCondition<ModuleConfig.DetectionSensorConfig>.isTrue(F.enabled)
		let sensing = ConfigFormCondition<ModuleConfig.DetectionSensorConfig>
			.all([enabled, .environment { _ in role == .sensor }])
		return .init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "dot.radiowaves.right",
					  control: .custom { config in AnyView(DetectionEnabledRows(config: config)) })
			]),
			.init(title: String(localized: "Sensor options", comment: "Settings section"),
				  shownWhen: sensing, fields: [
				.init(F.sendBell, symbol: "bell"),
				.init(F.name, symbol: "signature", byteCap: 20),
				.init(F.monitorPin, control: .gpioPin),
				.init(F.detectionTriggerType),
				.init(F.usePullup, symbol: "arrow.up.to.line")
			]),
			.init(title: String(localized: "Update Interval", comment: "Settings section"),
				  shownWhen: sensing, fields: [
				.init(F.minimumBroadcastSecs, control: .interval(.detectionSensorMinimum)),
				.init(F.stateBroadcastSecs, control: .interval(.detectionSensorState))
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Detection Sensor", overlay: Self.overlay(role: role),
			request: accessoryManager.requestDetectionSensorModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveDetectionSensorModuleConfig(config: config, fromUser: from, toUser: to)
			},
			trailing: { config in
				// Only reachable while the sensor sections are hidden, so it reads as the
				// section directly after Options rather than an afterthought at the end.
				if config.wrappedValue.enabled, role == .client {
					Section(header: Text("Client options")) {
						Toggle(isOn: $detectionNotificationsEnabled) {
							Label("Enable Notifications", systemImage: "bell.badge")
							Text("Detection sensor messages arrive as text messages. With notifications on you get one for each detection message received, and a matching unread badge.")
						}
					}
					.onChange(of: detectionNotificationsEnabled) { _, newValue in
						UserDefaults.enableDetectionNotifications = newValue
					}
				}
			})
		.navigationTitle("Detection Sensor Config")
	}
}

/// The enabled toggle, plus the app-side role choice it reveals.
private struct DetectionEnabledRows: View {
	@Binding var config: ModuleConfig.DetectionSensorConfig
	@AppStorage("detectionSensorRole") private var role: DetectionSensorRole = .sensor

	private static let metadata = FieldMetadataRegistry.get("meshtastic.ModuleConfig.DetectionSensorConfig", tag: 1)

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Toggle(isOn: $config.enabled) {
				Label(Self.metadata?.label ?? "Enabled", systemImage: "dot.radiowaves.right")
			}
			if let description = Self.metadata?.description {
				Text(description)
					.foregroundColor(.gray)
					.font(.callout)
			}
		}
		if config.enabled {
			Picker(selection: $role, label: Text("Role")) {
				ForEach(DetectionSensorRole.allCases, id: \.self) { role in
					Text(role.description).tag(role)
				}
			}
			.pickerStyle(SegmentedPickerStyle())
			.padding(.vertical, 5)
		}
	}
}
