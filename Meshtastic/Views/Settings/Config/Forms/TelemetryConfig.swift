//
//  TelemetryConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension ModuleConfig.TelemetryConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, TelemetryConfigEntity?> = \NodeInfoEntity.telemetryConfig

	init(entity: TelemetryConfigEntity) {
		self.init()
		deviceUpdateInterval = UInt32(truncatingIfNeeded: entity.deviceUpdateInterval)
		deviceTelemetryEnabled = entity.deviceTelemetryEnabled
		environmentUpdateInterval = UInt32(truncatingIfNeeded: entity.environmentUpdateInterval)
		environmentMeasurementEnabled = entity.environmentMeasurementEnabled
		environmentScreenEnabled = entity.environmentScreenEnabled
		environmentDisplayFahrenheit = entity.environmentDisplayFahrenheit
		airQualityEnabled = entity.airQualityEnabled
		airQualityInterval = UInt32(truncatingIfNeeded: entity.airQualityInterval)
		powerMeasurementEnabled = entity.powerMeasurementEnabled
		powerUpdateInterval = UInt32(truncatingIfNeeded: entity.powerUpdateInterval)
		powerScreenEnabled = entity.powerScreenEnabled
	}
}

struct TelemetryConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = ModuleConfig.TelemetryConfig.Fields
	private static let deviceToggleFirmware = "2.7.12"

	static func overlay() -> ConfigFormOverlay<ModuleConfig.TelemetryConfig> {
		let hasToggle = ConfigFormCondition<ModuleConfig.TelemetryConfig>.firmware(atLeast: deviceToggleFirmware)
		return .init(sections: [
			.init(title: String(localized: "Device Options", comment: "Settings section"), fields: [
				// Firmware before 2.7.12 has no toggle; the interval alone is shown there.
				.init(F.deviceTelemetryEnabled, symbol: "wifi", shownWhen: hasToggle),
				.init(F.deviceUpdateInterval, shownWhen: .any([.not(hasToggle), .isTrue(F.deviceTelemetryEnabled)]),
					  control: .interval(.broadcastShort))
			]),
			.init(title: String(localized: "Environment Sensor Options", comment: "Settings section"), fields: [
				.init(F.environmentMeasurementEnabled, symbol: "chart.xyaxis.line"),
				.init(F.environmentUpdateInterval, shownWhen: .isTrue(F.environmentMeasurementEnabled), control: .interval(.broadcastShort)),
				.init(F.environmentScreenEnabled, symbol: "display", shownWhen: .isTrue(F.environmentMeasurementEnabled)),
				.init(F.environmentDisplayFahrenheit, symbol: "thermometer", shownWhen: .isTrue(F.environmentMeasurementEnabled))
			]),
			.init(title: String(localized: "Air Quality Sensor Options", comment: "Settings section"), fields: [
				.init(F.airQualityEnabled, symbol: "aqi.medium"),
				.init(F.airQualityInterval, shownWhen: .isTrue(F.airQualityEnabled), control: .interval(.broadcastShort))
			]),
			.init(title: String(localized: "Power Sensor Options", comment: "Settings section"), fields: [
				.init(F.powerMeasurementEnabled, symbol: "bolt"),
				.init(F.powerUpdateInterval, shownWhen: .isTrue(F.powerMeasurementEnabled), control: .interval(.broadcastShort)),
				.init(F.powerScreenEnabled, symbol: "tv", shownWhen: .isTrue(F.powerMeasurementEnabled))
			])
		], omitted: [
			.init(F.healthMeasurementEnabled, "not yet offered by this client; unlabelled upstream"),
			.init(F.healthUpdateInterval, "not yet offered by this client; unlabelled upstream"),
			.init(F.healthScreenEnabled, "not yet offered by this client; unlabelled upstream"),
			.init(F.airQualityScreenEnabled, "not yet offered by this client; unlabelled upstream")
		])
	}

	/// Before the toggle existed, an interval of Int32.max meant "off".
	static func normalize(_ config: ModuleConfig.TelemetryConfig, legacy: Bool) -> ModuleConfig.TelemetryConfig {
		var c = config
		if legacy { c.deviceTelemetryEnabled = c.deviceUpdateInterval != UInt32(Int32.max) }
		return c
	}

	var body: some View {
		let legacy = !accessoryManager.checkIsVersionSupported(forVersion: Self.deviceToggleFirmware)
		MetadataConfigForm(
			node: node, title: "Telemetry", overlay: Self.overlay(),
			normalize: { Self.normalize($0, legacy: legacy) },
			request: accessoryManager.requestTelemetryModuleConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveTelemetryModuleConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Telemetry Config")
	}
}
