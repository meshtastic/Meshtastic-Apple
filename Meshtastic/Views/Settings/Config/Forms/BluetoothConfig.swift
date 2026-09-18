//
//  BluetoothConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

extension Config.BluetoothConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, BluetoothConfigEntity?> = \NodeInfoEntity.bluetoothConfig

	init(entity: BluetoothConfigEntity) {
		self.init()
		enabled = entity.enabled
		mode = PairingMode(rawValue: Int(entity.mode)) ?? .randomPin
		fixedPin = UInt32(truncatingIfNeeded: entity.fixedPin)
	}
}

struct BluetoothConfig: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?

	private typealias F = Config.BluetoothConfig.Fields

	static func overlay() -> ConfigFormOverlay<Config.BluetoothConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "antenna.radiowaves.left.and.right"),
				.init(F.mode),
				// Six digits, digits only, no leading zeros: the firmware stores the PIN as a
				// number. A plain number field would take anything.
				.init(F.fixedPin, shownWhen: .equals(F.mode, .fixedPin),
					  control: .custom { config in AnyView(BluetoothPINField(pin: config.fixedPin)) })
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Bluetooth", overlay: Self.overlay(),
			request: accessoryManager.requestBluetoothConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveBluetoothConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Bluetooth Config")
	}
}

/// The fixed pairing PIN: exactly six digits, kept as text while typing so a partial
/// entry can be shown as short rather than silently accepted.
private struct BluetoothPINField: View {
	@Binding var pin: UInt32
	@State private var text = ""
	private let length = 6

	private var label: String { Config.BluetoothConfig.Fields.fixedPin.metadata?.label ?? "Fixed Pin" }
	private var isShort: Bool { !text.isEmpty && text.count < length }

	var body: some View {
		HStack {
			Label(label, systemImage: "wallet.pass")
			TextField(label, text: $text)
				.foregroundColor(.gray)
				.multilineTextAlignment(.trailing)
				.keyboardType(.numberPad)
		}
		.onAppear { text = pin == 0 ? "" : String(pin) }
		.onChange(of: text) { _, new in
			let digits = String(new.filter(\.isNumber).drop(while: { $0 == "0" }).prefix(length))
			if digits != new { text = digits }
			if digits.count == length, let value = UInt32(digits) { pin = value }
		}
		.onChange(of: pin) { _, new in
			let shown = new == 0 ? "" : String(new)
			if shown != text, text.count == length || text.isEmpty { text = shown }
		}
		if isShort {
			Text("BLE Pin must be 6 digits long.")
				.font(.callout)
				.foregroundColor(.red)
		}
	}
}
