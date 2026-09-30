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
		// "ESP32 only" in the firmware means the whole family. Power saving and the
		// battery section have only ever been offered on esp32 and esp32-s3, so they
		// keep that check; the Bluetooth wait uses the wider one.
		let esp32Family = esp32 || architecture == .esp32C3 || architecture == .esp32C6
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
				.init(F.onBatteryShutdownAfterSecs, symbol: "power", control: .nonZeroToggle(onValue: 1800)),
				// How long the board holds BLE up in a no-Bluetooth state before turning it
				// off. ESP32 only, and zero is the firmware default of one minute.
				.init(F.waitBluetoothSecs, symbol: "dot.radiowaves.right",
					  shownWhen: .environment { _ in esp32Family }, control: .interval(.waitBluetooth))
			]),
			.init(title: String(localized: "Battery", comment: "Settings section"), shownWhen: .environment { _ in esp32 }, fields: [
				.init(F.adcMultiplierOverride, control: .custom { config in AnyView(ADCOverrideField(multiplier: config.adcMultiplierOverride)) })
			])
		], omitted: [
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
/// How the ADC override switch and the message relate.
///
/// Its own type so the rules can be tested without rendering: the switch state is read from
/// the multiplier rather than copied into `@State`, which is what stopped a stored override
/// showing when the screen opened.
enum ADCOverride {
	/// Where the number starts when the override is switched on with nothing to restore. The
	/// field documents a range of two to six, so this is the low end of it — a starting point
	/// to correct, not a recommendation.
	static let startingMultiplier: Float = 2

	/// Zero is how the message stores "no override", so it is also how the switch reads off.
	static func isOn(_ multiplier: Float) -> Bool { multiplier != 0 }

	/// The multiplier to store when the switch moves. Switching off keeps nothing, so the
	/// caller holds the last number to put back.
	static func multiplier(switchedOn on: Bool, remembered: Float) -> Float {
		guard on else { return 0 }
		return remembered > 0 ? remembered : startingMultiplier
	}
}

private struct ADCOverrideField: View {
	@Binding var multiplier: Float

	/// The number being edited, which the message cannot hold on its own: switching the
	/// override off stores zero, and the value has to survive that to come back when it is
	/// switched on again. Kept in step with the message below rather than copied on appear.
	@State private var typed: Float = 0

	private static let label = FieldMetadataRegistry.get("meshtastic.Config.PowerConfig", tag: 3)?.label ?? "ADC Override"

	/// Read from the message rather than copied out of it on appear.
	///
	/// This row is built before the form has loaded the config, so a copy taken then reads
	/// zero and the switch shows off on a radio that has an override stored. Worse, switching
	/// it on and off again from there writes zero over the stored value.
	private var overriding: Binding<Bool> {
		Binding(
			get: { ADCOverride.isOn(multiplier) },
			set: { on in multiplier = ADCOverride.multiplier(switchedOn: on, remembered: typed) }
		)
	}

	var body: some View {
		Toggle(isOn: overriding) {
			Text(Self.label)
		}
		.onChange(of: multiplier, initial: true) { _, new in
			// Follows the message, including the first time the form fills it in. Zero is the
			// off state rather than a multiplier, so the last real value stays to be restored.
			if new > 0 { typed = new }
		}
		if ADCOverride.isOn(multiplier) {
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
