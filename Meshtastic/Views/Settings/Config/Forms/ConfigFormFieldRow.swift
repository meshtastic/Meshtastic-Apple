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
