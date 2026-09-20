//
//  ConfigFormFieldRow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs

/// One row of a metadata-driven form: the control for a field, its label from the
/// registry, and its description beneath.
///
/// The control is chosen from the field's kind and metadata unless the overlay says
/// otherwise. Each kind is its own small view so the type checker never sees the whole
/// switch as one expression - the hand-written screens hit that wall and had to split
/// their bodies to get past it.
struct ConfigFormFieldRow<M: ConfigSchemaMessage>: View {
	let field: ConfigFormField<M>
	@Binding var config: M
	let environment: ConfigFormEnvironment

	private var metadata: FieldMetadata? { field.field.metadata }

	/// The registry label, or the proto name made readable. The test that every
	/// laid-out field has a label means the fallback never ships.
	private var label: String {
		metadata?.label ?? field.field.name.split(separator: ".").last.map {
			$0.replacingOccurrences(of: "_", with: " ").capitalized
		} ?? field.field.name
	}

	var body: some View {
		switch field.control {
		case .custom(let make):
			make($config)
		case .flags(let flags):
			// One row per bit, not one row holding them all: a Form section draws a
			// VStack as a single row, and these are separate settings.
			FlagRows(flags: flags, description: metadata?.description,
					 config: $config, environment: environment, value: integerBinding)
		default:
			VStack(alignment: .leading, spacing: 4) {
				control
				if let description = metadata?.description {
					Text(description)
						.foregroundColor(.gray)
						.font(.callout)
				}
				if field.field.isDeprecated {
					Label(String(localized: "Deprecated", comment: "Config field marker"), systemImage: "exclamationmark.triangle")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			}
		}
	}

	/// The field's integer binding, for a control that reads the whole word rather than
	/// one typed value. Only `.flags` uses this, and the overlay test rejects `.flags`
	/// on anything but an integer field.
	private var integerBinding: Binding<Int> {
		if case .integer(let make) = field.value { return make($config) }
		return .constant(0)
	}

	@ViewBuilder
	private var control: some View {
		switch field.value {
		case .bool(let make):
			BoolRow(label: label, symbol: field.symbol, isOn: field.inverted ? make($config).negated : make($config))
		case .integer(let make):
			IntegerRow(field: field, label: label, metadata: metadata, environment: environment,
					   value: make($config).showingDefault(field.displayDefault))
		case .float(let make):
			FloatRow(label: label, symbol: field.symbol, value: make($config))
		case .string(let make):
			StringRow(field: field, label: label, text: make($config))
		case .enumeration(let make, let cases, let caseName):
			EnumRow(field: field, label: label, environment: environment, cases: cases, caseName: caseName, selection: make($config))
		case .unsupported:
			// Only reachable if an overlay lays out an unsupported field without a
			// custom control; the overlay test rejects that.
			Text(label).foregroundStyle(.secondary)
		}
	}
}

// MARK: - Rows by kind

private struct BoolRow: View {
	let label: String
	let symbol: String?
	@Binding var isOn: Bool

	var body: some View {
		Toggle(isOn: $isOn) {
			if let symbol {
				Label(label, systemImage: symbol)
			} else {
				Text(label)
			}
		}
	}
}

private struct IntegerRow<M: ConfigSchemaMessage>: View {
	let field: ConfigFormField<M>
	let label: String
	let metadata: FieldMetadata?
	let environment: ConfigFormEnvironment
	@Binding var value: Int

	var body: some View {
		if case .nonZeroToggle(let onValue, let inner) = field.control {
			NonZeroToggle(label: label, symbol: field.symbol, onValue: Int(onValue), value: $value) {
				// The toggle above already carries the field's one label, so the value
				// control beneath it shows the value alone rather than repeating it.
				plain(inner, bare: true)
			}
		} else {
			plain(field.control, bare: false)
		}
	}

	/// Every integer control but the non-zero toggle, which wraps one of these.
	@ViewBuilder
	private func plain(_ control: ConfigFormControl<M>, bare: Bool) -> some View {
		let rowLabel = bare ? "" : label
		switch control {
		case .ipv4Address(let required):
			IPv4Row(label: rowLabel, symbol: field.symbol, required: required, value: $value)
		case .gpioPin:
			GPIOPinPicker(title: rowLabel, selection: $value)
		case .interval(let configuration):
			UpdateIntervalPicker(config: configuration, pickerLabel: LocalizedStringKey(rowLabel), selectedInterval: $value.asInterval)
		case .options(let options):
			Picker(rowLabel, selection: $value) {
				ForEach(options) { option in
					Text(option.title).tag(option.value)
				}
			}
		case .stepper:
			bounded(preferSlider: false, bare: bare)
		case .slider:
			bounded(preferSlider: true, bare: bare)
		default:
			automatic(bare: bare)
		}
	}

	/// Bounds in the registry make a stepper; a seconds unit makes an interval picker;
	/// anything else is a number field with the unit beside it.
	@ViewBuilder
	private func automatic(bare: Bool) -> some View {
		if metadata?.minValue != nil, metadata?.maxValue != nil {
			bounded(preferSlider: false, bare: bare)
		} else if metadata?.unit == "s" {
			UpdateIntervalPicker(config: .all, pickerLabel: LocalizedStringKey(bare ? "" : label), selectedInterval: $value.asInterval)
		} else {
			numberField(bare: bare)
		}
	}

	@ViewBuilder
	private func bounded(preferSlider: Bool, bare: Bool) -> some View {
		let lower = Int(metadata?.minValue ?? 0)
		let upper = Int(metadata?.maxValue ?? Double(Int32.max))
		if preferSlider || upper - lower > 32 {
			VStack(alignment: .leading) {
				HStack {
					if !bare { Text(label) }
					Spacer()
					Text(valueWithUnit).foregroundStyle(.secondary)
				}
				Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) }),
					   in: Double(lower)...Double(upper), step: 1)
			}
		} else {
			Stepper(value: $value, in: lower...upper) {
				HStack {
					if !bare { Text(label) }
					Spacer()
					Text(valueWithUnit).foregroundStyle(.secondary)
				}
			}
		}
	}

	private func numberField(bare: Bool) -> some View {
		HStack {
			if !bare {
				// The registry's names are longer than the ones these screens used to
				// hardcode, so the label claims its width first; the number needs little.
				// (Sizing the field instead does the opposite: a TextField's ideal width
				// comes from its placeholder, which is this same label.)
				Group {
					if let symbol = field.symbol {
						Label(label, systemImage: symbol)
					} else {
						Text(label)
					}
				}
				.layoutPriority(1)
			}
			Spacer()
			// The placeholder keeps the field's name for VoiceOver even when the row is bare.
			TextField(label, value: $value, format: .number)
				.multilineTextAlignment(.trailing)
				.keyboardType(.numbersAndPunctuation)
				.foregroundColor(.gray)
			if let unit = metadata?.unit {
				Text(unit).foregroundColor(.gray)
			}
		}
	}

	private var valueWithUnit: String {
		if let unit = metadata?.unit { return "\(value) \(unit)" }
		return "\(value)"
	}
}

/// "Zero means off": a toggle, and the value control beneath it while on.
private struct NonZeroToggle<Inner: View>: View {
	let label: String
	let symbol: String?
	let onValue: Int
	@Binding var value: Int
	@ViewBuilder let inner: () -> Inner

	var body: some View {
		Toggle(isOn: Binding(get: { value != 0 }, set: { value = $0 ? (value == 0 ? onValue : value) : 0 })) {
			if let symbol {
				Label(label, systemImage: symbol)
			} else {
				Text(label)
			}
		}
		if value != 0 {
			inner()
		}
	}
}

private struct FloatRow: View {
	let label: String
	let symbol: String?
	@Binding var value: Double

	var body: some View {
		HStack {
			if let symbol {
				Label(label, systemImage: symbol)
			} else {
				Text(label)
			}
			Spacer()
			TextField(label, value: $value, format: .number)
				.multilineTextAlignment(.trailing)
				.keyboardType(.decimalPad)
				.foregroundColor(.gray)
		}
	}
}

private struct StringRow<M: ConfigSchemaMessage>: View {
	let field: ConfigFormField<M>
	let label: String
	@Binding var text: String

	var body: some View {
		// Label beside the field, as the old screens laid it out; the placeholder alone
		// disappears as soon as there is a value.
		HStack {
			if let symbol = field.symbol {
				Label(label, systemImage: symbol)
			} else {
				Text(label)
			}
			Group {
				if case .secure = field.control {
					SecureField(label, text: $text)
				} else {
					TextField(label, text: $text, axis: .vertical)
				}
			}
			.foregroundColor(.gray)
			.multilineTextAlignment(.trailing)
			// Config strings are identifiers - topics, addresses, a TZ rule - never prose.
			.autocorrectionDisabled()
			.textInputAutocapitalization(.never)
		}
		.onChange(of: text) { _, new in
			// The twelve UTF-8 truncation loops the old screens carried, once.
			guard let cap = field.byteCap else { return }
			var trimmed = new
			while trimmed.utf8.count > cap { trimmed = String(trimmed.dropLast()) }
			if trimmed != new { text = trimmed }
		}
	}
}

private struct EnumRow<M: ConfigSchemaMessage>: View {
	let field: ConfigFormField<M>
	let label: String
	let environment: ConfigFormEnvironment
	let cases: [Int]
	let caseName: (Int) -> String
	@Binding var selection: Int

	private var enumType: String? { field.field.enumTypeName }

	/// Live values, in overlay order if given; deprecated values only while current; the
	/// current value always present so the picker has a matching tag even when newer
	/// firmware sent something this build does not know.
	private var options: [Int] {
		var values = field.enumValues?(environment) ?? cases
		if let order = field.enumOrder {
			values = order.filter { values.contains($0) } + values.filter { !order.contains($0) }
		}
		values = values.filter { $0 == selection || meta($0)?.deprecated != true }
		if !values.contains(selection) { values.append(selection) }
		return values
	}

	private func meta(_ raw: Int) -> FieldMetadata? {
		guard let enumType else { return nil }
		return FieldMetadataRegistry.get(enumType, tag: raw)
	}

	/// The registry label; failing that the case name made readable ("veDirect" ->
	/// "Ve Direct"), which is what a value looks like until it is annotated upstream.
	private func title(_ raw: Int) -> String {
		if let label = meta(raw)?.label { return label }
		if cases.contains(raw) {
			let name = caseName(raw)
			let spaced = name.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
			return spaced.prefix(1).uppercased() + spaced.dropFirst()
		}
		return String(localized: "Unknown (\(raw))", comment: "Enum value this build does not know")
	}

	var body: some View {
		Picker(label, selection: $selection) {
			ForEach(options, id: \.self) { raw in
				Text(title(raw)).tag(raw)
			}
		}
		.modifier(SegmentedIfAsked(segmented: { if case .segmented = field.control { return true }; return false }()))
		// A value can carry its own explanation upstream (device roles do); show the
		// selected one's beneath the picker.
		if let description = meta(selection)?.description {
			Text(description)
				.foregroundColor(.gray)
				.font(.callout)
		}
	}
}

private struct SegmentedIfAsked: ViewModifier {
	let segmented: Bool
	func body(content: Content) -> some View {
		if segmented {
			content.pickerStyle(.segmented)
		} else {
			content
		}
	}
}

// MARK: - Binding helpers

private extension Binding where Value == Bool {
	var negated: Binding<Bool> {
		Binding<Bool>(get: { !self.wrappedValue }, set: { self.wrappedValue = !$0 })
	}
}

private extension Binding where Value == Int {
	/// A stored zero reads as the default the firmware would apply; writing it back
	/// unchanged leaves the stored zero alone.
	func showingDefault(_ fallback: Int?) -> Binding<Int> {
		guard let fallback else { return self }
		return Binding<Int>(get: { self.wrappedValue == 0 ? fallback : self.wrappedValue }, set: { self.wrappedValue = $0 })
	}

	var asInterval: Binding<UpdateInterval> {
		Binding<UpdateInterval>(get: { UpdateInterval(from: self.wrappedValue) }, set: { self.wrappedValue = $0.intValue })
	}
}

/// A bitfield as one toggle per bit. The labels come from the flags' own enum value
/// metadata, so the words are the schema's; only which bits a screen offers, and which
/// of them depend on another being set, are stated in the overlay.
private struct FlagRows<M: ConfigSchemaMessage>: View {
	let flags: [ConfigFormFlag<M>]
	let description: String?
	@Binding var config: M
	let environment: ConfigFormEnvironment
	@Binding var value: Int

	var body: some View {
		if let description {
			Text(description)
				.foregroundColor(.gray)
				.font(.callout)
		}
		ForEach(flags.filter { $0.shownWhen?.evaluate(config, environment) ?? true }, id: \.rawValue) { flag in
			Toggle(isOn: binding(for: flag.rawValue)) {
				if let symbol = flag.symbol {
					Label(flag.label() ?? "", systemImage: symbol)
				} else {
					Text(flag.label() ?? "")
				}
			}
		}
	}

	private func binding(for bit: Int) -> Binding<Bool> {
		Binding(
			get: { ConfigFormFlagBits.isSet(bit, in: value) },
			set: { value = ConfigFormFlagBits.setting(bit, to: $0, in: value) })
	}
}

/// The bit arithmetic behind a flags row, separated so it can be tested without
/// rendering: a toggle must change its own bit and leave every other one alone.
enum ConfigFormFlagBits {
	static func isSet(_ bit: Int, in word: Int) -> Bool { word & bit != 0 }

	static func setting(_ bit: Int, to isOn: Bool, in word: Int) -> Int {
		isOn ? word | bit : word & ~bit
	}
}

/// A uint32 IPv4 address, typed and shown as a dotted quad. The radio stores the
/// address as a number; nobody reads one that way, and a half-typed address must not
/// be silently written as 0.0.0.0, so the text is kept as text while it is being
/// edited and only converted when it parses.
struct IPv4Row: View {
	let label: String
	let symbol: String?
	/// A blank address reads as invalid: a static configuration cannot work without it.
	let required: Bool
	@Binding var value: Int
	@State private var text: String = ""
	@State private var editing = false

	private var isValid: Bool {
		required ? IPv4Address.isRequiredFieldValid(text) : IPv4Address.isFieldValid(text)
	}

	var body: some View {
		HStack {
			if let symbol {
				Label(label, systemImage: symbol)
			} else {
				Text(label)
			}
			Spacer()
			TextField(required ? "192.168.1.10" : String(localized: "Optional", comment: "Optional address field"),
					  text: $text)
				.multilineTextAlignment(.trailing)
				.foregroundColor(isValid ? .gray : .red)
				.keyboardType(.numbersAndPunctuation)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
				.onChange(of: text) { _, new in
					// Text that does not parse writes 0, which reads as unset. Keeping the
					// previous value instead would be worse: the field would show a typo
					// in red while the form still held the old address, and saving would
					// quietly write that old address back.
					value = Int(IPv4Address.toUInt32(new))
				}
				.onAppear { text = IPv4Address.toString(UInt32(truncatingIfNeeded: value)) }
				.onChange(of: value) { _, new in
					// The radio's values arriving after the form opened, not the user typing.
					let incoming = IPv4Address.toString(UInt32(truncatingIfNeeded: new))
					if incoming != text, IPv4Address.toUInt32(text) != UInt32(truncatingIfNeeded: new) {
						text = incoming
					}
				}
		}
	}
}

/// IPv4 in the shape the radio stores it and the shape people type it.
enum IPv4Address {
	/// A well-formed dotted quad, or blank. Each octet is 1-3 ASCII digits in range,
	/// which also rejects the signs and whitespace `UInt32` alone would accept: without
	/// that, a typo like `192.168.1` or `192.168.1.300` becomes 0.0.0.0 silently.
	static func isFieldValid(_ text: String) -> Bool {
		if text.isEmpty { return true }
		let parts = text.split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count == 4 else { return false }
		return parts.allSatisfy { part in
			guard part.count <= 3,
				  part.allSatisfy({ $0.isASCII && $0.isNumber }),
				  let value = UInt32(part) else { return false }
			return value <= 255
		}
	}

	/// For an address a static configuration cannot go without. Anything that packs to
	/// zero is a fault here, which covers blank and `0.0.0.0` alike: both store as zero,
	/// and a row that reads as valid while the save is blocked explains nothing.
	static func isRequiredFieldValid(_ text: String) -> Bool {
		isFieldValid(text) && toUInt32(text) != 0
	}

	/// Zero for anything the strict check rejects. Parsing leniently here would let the
	/// two disagree: `split` drops a trailing empty component, so `192.168.1.1.` would
	/// pack to a perfectly good address while the field showed it in red, and the save
	/// gate reads the packed value.
	static func toUInt32(_ text: String) -> UInt32 {
		guard isFieldValid(text) else { return 0 }
		let parts = text.split(separator: ".").compactMap { UInt32($0) }
		guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return 0 }
		return parts[0] | (parts[1] << 8) | (parts[2] << 16) | (parts[3] << 24)
	}

	/// Zero round-trips as blank, which is how the firmware reports an unset address.
	static func toString(_ value: UInt32) -> String {
		if value == 0 { return "" }
		return "\(value & 0xFF).\((value >> 8) & 0xFF).\((value >> 16) & 0xFF).\((value >> 24) & 0xFF)"
	}
}
