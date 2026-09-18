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

	/// A PIN being typed can be too short to save. The field reports that here so the
	/// Save button can wait for the sixth digit.
	@State private var pinIsComplete = true

	private typealias F = Config.BluetoothConfig.Fields

	/// The radio only uses the PIN on fixed-pin pairing, so a short one holds Save back
	/// only there.
	static func canSave(_ config: Config.BluetoothConfig, pinIsComplete: Bool) -> Bool {
		config.mode != .fixedPin || pinIsComplete
	}

	static func overlay(pinIsComplete: Binding<Bool> = .constant(true)) -> ConfigFormOverlay<Config.BluetoothConfig> {
		.init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				.init(F.enabled, symbol: "antenna.radiowaves.left.and.right"),
				.init(F.mode),
				// Six digits, digits only, no leading zeros: the firmware stores the PIN as a
				// number. A plain number field would take anything.
				.init(F.fixedPin, shownWhen: .equals(F.mode, .fixedPin),
					  control: .custom { config in
						  AnyView(BluetoothPINField(pin: config.fixedPin, isComplete: pinIsComplete))
					  })
			])
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "Bluetooth", overlay: Self.overlay(pinIsComplete: $pinIsComplete),
			canSave: { Self.canSave($0, pinIsComplete: pinIsComplete) },
			request: accessoryManager.requestBluetoothConfig,
			save: { config, from, to in
				_ = try await accessoryManager.saveBluetoothConfig(config: config, fromUser: from, toUser: to)
			})
		.navigationTitle("Bluetooth Config")
	}
}

/// The fixed pairing PIN: exactly six digits, kept as text while typing so a partial
/// entry can be shown as short rather than silently accepted. What is typed is written
/// through as it is typed, so the PIN on screen is always the one that would be saved,
/// and a short one holds the Save button back rather than sending the previous value.
private struct BluetoothPINField: View {
	@Binding var pin: UInt32
	@Binding var isComplete: Bool
	@State private var text = ""
	private let length = 6

	private var label: String { Config.BluetoothConfig.Fields.fixedPin.metadata?.label ?? "Fixed Pin" }

	var body: some View {
		HStack {
			Label(label, systemImage: "wallet.pass")
			TextField(label, text: $text)
				.foregroundColor(.gray)
				.multilineTextAlignment(.trailing)
				.keyboardType(.numberPad)
		}
		.onAppear {
			text = pin == 0 ? "" : String(pin)
			isComplete = text.count == length
		}
		.onChange(of: text) { _, new in
			let digits = String(new.filter(\.isNumber).drop(while: { $0 == "0" }).prefix(length))
			if digits != new { text = digits }
			pin = UInt32(digits) ?? 0
			isComplete = digits.count == length
		}
		.onChange(of: pin) { _, new in
			// A config arriving from the radio replaces what is shown; setting the text
			// runs the handler above, which reports whether it is complete.
			let shown = new == 0 ? "" : String(new)
			if shown != text { text = shown }
		}
		if !isComplete {
			Text("BLE Pin must be 6 digits long.")
				.font(.callout)
				.foregroundColor(.red)
		}
	}
}
