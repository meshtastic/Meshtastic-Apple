//
//  PowerConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
@preconcurrency import SwiftData
import OSLog
import MeshtasticProtobufs

extension Config.PowerConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, PowerConfigEntity?> = \NodeInfoEntity.powerConfig

	init(entity: PowerConfigEntity) {
		self.init()
		isPowerSaving = entity.isPowerSaving
		onBatteryShutdownAfterSecs = UInt32(truncatingIfNeeded: entity.onBatteryShutdownAfterSecs)
		adcMultiplierOverride = entity.adcMultiplierOverride
		waitBluetoothSecs = UInt32(truncatingIfNeeded: entity.waitBluetoothSecs)
		lsSecs = UInt32(truncatingIfNeeded: entity.lsSecs)
		minWakeSecs = UInt32(truncatingIfNeeded: entity.minWakeSecs)
		deviceBatteryInaAddress = UInt32(truncatingIfNeeded: entity.deviceBatteryInaAddress)
	}
}

struct PowerConfig: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	/// Resolved from the hardware catalog on appear. Until then, and for hardware the
	/// catalog does not know, the architecture-specific rows stay hidden as before.
	@State private var architecture: Architecture?

	private typealias F = Config.PowerConfig.Fields

	static func overlay(architecture: Architecture? = nil) -> ConfigFormOverlay<Config.PowerConfig> {
		let esp32 = architecture == .esp32 || architecture == .esp32S3
		// Power saving sleeps the radio too, so it is only offered where the firmware
		// honours it: ESP32 boards, and nRF52 boards in the tracker or sensor role.
		let canPowerSave = ConfigFormCondition<Config.PowerConfig>.environment { env in
			let role = env.node?.deviceConfig.map { Config.DeviceConfig.Role(rawValue: Int($0.role)) } ?? nil
			return esp32 || (architecture == .nrf52840 && (role == .tracker || role == .sensor))
		}
		return .init(sections: [
			.init(title: String(localized: "Power", comment: "Settings section"), fields: [
				.init(F.isPowerSaving, symbol: "bolt", shownWhen: canPowerSave),
				// Half an hour when switched on; the old screen left the picker unset, which saved as off.
				.init(F.onBatteryShutdownAfterSecs, symbol: "power", control: .nonZeroToggle(onValue: 1800))
			]),
			.init(title: String(localized: "Battery", comment: "Settings section"), shownWhen: .environment { _ in esp32 }, fields: [
				.init(F.adcMultiplierOverride, control: .custom { config in AnyView(ADCOverrideField(multiplier: config.adcMultiplierOverride)) })
			])
		], omitted: [
			.init(F.waitBluetoothSecs, "not offered by this client; round-trips from the entity"),
			.init(F.sdsSecs, "not offered by this client; not stored by the entity, so saved as the proto default as before"),
			.init(F.lsSecs, "not offered by this client; round-trips from the entity"),
			.init(F.minWakeSecs, "not offered by this client; round-trips from the entity"),
			.init(F.deviceBatteryInaAddress, "not offered by this client; round-trips from the entity"),
			.init(F.powermonEnables, "not offered by this client; not stored by the entity, so saved as the proto default as before")
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Power", overlay: Self.overlay(architecture: architecture),
			request: accessoryManager.requestPowerConfig,
			save: { config, from, to in
				_ = try await accessoryManager.savePowerConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Power Config")
		.onFirstAppear(resolveArchitecture)
	}

	private func resolveArchitecture() {
		guard let hwModelId = node?.user?.hwModelId else { return }
		let hwModelValue = Int64(hwModelId)
		let descriptor = FetchDescriptor<DeviceHardwareEntity>(predicate: #Predicate { $0.hwModel == hwModelValue })
		do {
			let hardware = try context.fetch(descriptor)
			if let archString = HardwareCatalogResolver.presentation(for: hwModelValue, in: hardware)?.architecture,
			   let arch = Architecture(rawValue: archString) {
				architecture = arch
			}
		} catch {
			// The rows this gates stay hidden, which looks like hardware that does not
			// support them. Say so rather than letting the screen quietly lose them.
			Logger.data.error("Could not read the hardware catalog for the power screen: \(error.localizedDescription, privacy: .public)")
		}
	}
}

/// The ADC multiplier as the old screen offered it: a toggle, and the number while on.
/// Zero means no override, so switching off clears the value.
private struct ADCOverrideField: View {
	@Binding var multiplier: Float
	@State private var overriding = false
	@State private var typed: Float = 0

	private static let label = FieldMetadataRegistry.get("meshtastic.Config.PowerConfig", tag: 3)?.label ?? "ADC Override"

	var body: some View {
		Toggle(isOn: $overriding) {
			Text(Self.label)
		}
		.onAppear {
			overriding = multiplier != 0
			typed = multiplier
		}
		.onChange(of: overriding) { _, on in
			// Switching back on has to restore what is on screen: leaving `multiplier`
			// at zero would save "no override" while the field shows a value.
			multiplier = on ? (typed > 0 ? typed : multiplier) : 0
		}
		if overriding {
			HStack {
				Text("Multiplier")
				Spacer()
				TextField("Multiplier", value: $typed, format: .number)
					.multilineTextAlignment(.trailing)
					.keyboardType(.decimalPad)
					.foregroundColor(.gray)
					.onChange(of: typed) { _, new in
						// Only a positive multiplier makes sense; anything else reverts.
						if new > 0 { multiplier = new } else { typed = multiplier }
					}
			}
		}
	}
}
