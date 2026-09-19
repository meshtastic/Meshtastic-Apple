//
//  ConfigFormOverlay.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI
import MeshtasticProtobufs
import SwiftProtobuf

/// How one configuration screen lays out its schema fields.
///
/// The schema says which fields exist and what kind they are; the registry says what
/// they are called. Neither says which fields sit together, in what order, or that
/// "Fixed Pin" only matters while the pairing mode is fixed-pin. That is this. It holds
/// no display text of its own - section titles are the only strings, and they are
/// localized at the call site - so there is nothing here for translators or other
/// clients, which is why it is Swift rather than a data file: a field the schema renames
/// fails to compile instead of failing to render.
///
/// If the schema ever carries a section, order or dependency attribute, the entries here
/// that restate it become redundant and `ConfigFormOverlayTests` says so, field by field.
struct ConfigFormOverlay<M: ConfigSchemaMessage> {
	var sections: [ConfigFormSection<M>]
	/// Fields deliberately not rendered, each with a reason. The completeness test asks
	/// that every renderable field of `M` be laid out or listed here.
	var omitted: [ConfigFormOmission<M>] = []

	/// The row a search result names, or nil when this screen does not lay that field
	/// out. Identity rather than tag: a flattened child field carries its own message's
	/// name, so tags alone would collide.
	func omits(_ identity: FieldIdentity) -> Bool {
		omitted.contains { $0.identity == identity }
	}

	func rowID(for identity: FieldIdentity) -> String? {
		if let row = sections.flatMap(\.fields).first(where: { $0.field.identity == identity })?.id {
			return row
		}
		// A field folded into another control is still its own entry in the index, so
		// send the reader to the control that writes it rather than nowhere.
		guard let covered = omitted.first(where: { $0.identity == identity })?.coveredBy else { return nil }
		return sections.flatMap(\.fields).first { $0.field.identity == covered }?.id
	}

}

struct ConfigFormSection<M: ConfigSchemaMessage>: Identifiable {
	let id = UUID()
	var title: String?
	var footer: String?
	var shownWhen: ConfigFormCondition<M>?
	/// Greyed out as a whole, for a screen where a preset takes over its fields.
	var enabledWhen: ConfigFormCondition<M>?
	var fields: [ConfigFormField<M>]

	init(
		title: String? = nil, footer: String? = nil, shownWhen: ConfigFormCondition<M>? = nil,
		enabledWhen: ConfigFormCondition<M>? = nil, fields: [ConfigFormField<M>]
	) {
		self.title = title
		self.footer = footer
		self.shownWhen = shownWhen
		self.enabledWhen = enabledWhen
		self.fields = fields
	}
}

/// How a row reads and writes its field, with the value type erased.
///
/// Chosen at the overlay call site by overload, so the compiler picks the case that
/// matches the field's type and no cast is needed at runtime. Integers travel as `Int`
/// whatever their proto width; enums as their raw value, with the live cases alongside.
enum ConfigFormValue<M: ConfigSchemaMessage> {
	case bool((Binding<M>) -> Binding<Bool>)
	case integer((Binding<M>) -> Binding<Int>)
	case float((Binding<M>) -> Binding<Double>)
	case string((Binding<M>) -> Binding<String>)
	case enumeration((Binding<M>) -> Binding<Int>, cases: [Int], caseName: (Int) -> String)
	/// Message, bytes and 64-bit fields: only a `.custom` control can render these.
	case unsupported
}

/// One laid-out field: which schema field, and anything about its presentation the
/// schema cannot say.
struct ConfigFormField<M: ConfigSchemaMessage>: Identifiable {
	let field: AnyConfigField<M>
	let value: ConfigFormValue<M>
	/// SF Symbol for the row's label. Presentation only.
	var symbol: String?
	var shownWhen: ConfigFormCondition<M>?
	var enabledWhen: ConfigFormCondition<M>?
	var control: ConfigFormControl<M>
	/// UTF-8 byte cap for a string field, until the schema carries `max_bytes`.
	var byteCap: Int?
	/// The control shows the negation of a Bool field ("LED Heartbeat" for
	/// `led_heartbeat_disabled`).
	var inverted: Bool
	/// Raw values in display order for an enum field; nil keeps declaration order.
	var enumOrder: [Int]?
	/// Which raw values to offer, when the set depends on the radio; nil offers all live
	/// values plus the current one if it is deprecated.
	var enumValues: ((ConfigFormEnvironment) -> [Int])?
	/// A stored zero reads as this value in the control - the "0 means the firmware
	/// default of 4 hours" pattern. Leaving it alone still saves 0.
	var displayDefault: Int?

	/// The proto name, dotted for a flattened nested field. Not the tag: a nested
	/// field shares its tag space with the parent's, so `ipv4_config.ip` and
	/// `wifi_enabled` are both tag 1 on NetworkConfig.
	var id: String { field.name }

	private init<V>(
		erasing field: ConfigField<M, V>, value: ConfigFormValue<M>, symbol: String?,
		shownWhen: ConfigFormCondition<M>?, enabledWhen: ConfigFormCondition<M>?,
		control: ConfigFormControl<M>, byteCap: Int?, inverted: Bool,
		enumOrder: [Int]?, enumValues: ((ConfigFormEnvironment) -> [Int])?, displayDefault: Int?
	) {
		guard let erased = M.allFields.first(where: { $0.tag == field.tag && $0.name == field.name }) else {
			preconditionFailure("\(M.protoName).\(field.name) is not in the generated schema")
		}
		self.field = erased
		self.value = value
		self.symbol = symbol
		self.shownWhen = shownWhen
		self.enabledWhen = enabledWhen
		self.control = control
		self.byteCap = byteCap
		self.inverted = inverted
		self.enumOrder = enumOrder
		self.enumValues = enumValues
		self.displayDefault = displayDefault
	}

	init(
		_ field: ConfigField<M, Bool>, symbol: String? = nil, shownWhen: ConfigFormCondition<M>? = nil,
		enabledWhen: ConfigFormCondition<M>? = nil, control: ConfigFormControl<M> = .automatic, inverted: Bool = false
	) {
		self.init(
			erasing: field, value: .bool { $0[dynamicMember: field.keyPath] }, symbol: symbol, shownWhen: shownWhen,
			enabledWhen: enabledWhen, control: control, byteCap: nil, inverted: inverted,
			enumOrder: nil, enumValues: nil, displayDefault: nil
		)
	}

	init(
		_ field: ConfigField<M, UInt32>, symbol: String? = nil, shownWhen: ConfigFormCondition<M>? = nil,
		enabledWhen: ConfigFormCondition<M>? = nil, control: ConfigFormControl<M> = .automatic, displayDefault: Int? = nil
	) {
		let make: (Binding<M>) -> Binding<Int> = { m in
			Binding(get: { Int(m.wrappedValue[keyPath: field.keyPath]) },
					set: { m.wrappedValue[keyPath: field.keyPath] = UInt32(clamping: $0) })
		}
		self.init(
			erasing: field, value: .integer(make), symbol: symbol, shownWhen: shownWhen, enabledWhen: enabledWhen,
			control: control, byteCap: nil, inverted: false, enumOrder: nil, enumValues: nil, displayDefault: displayDefault
		)
	}

	init(
		_ field: ConfigField<M, Int32>, symbol: String? = nil, shownWhen: ConfigFormCondition<M>? = nil,
		enabledWhen: ConfigFormCondition<M>? = nil, control: ConfigFormControl<M> = .automatic, displayDefault: Int? = nil
	) {
		let make: (Binding<M>) -> Binding<Int> = { m in
			Binding(get: { Int(m.wrappedValue[keyPath: field.keyPath]) },
					set: { m.wrappedValue[keyPath: field.keyPath] = Int32(clamping: $0) })
		}
		self.init(
			erasing: field, value: .integer(make), symbol: symbol, shownWhen: shownWhen, enabledWhen: enabledWhen,
			control: control, byteCap: nil, inverted: false, enumOrder: nil, enumValues: nil, displayDefault: displayDefault
		)
	}

	init(
		_ field: ConfigField<M, Float>, symbol: String? = nil, shownWhen: ConfigFormCondition<M>? = nil,
		enabledWhen: ConfigFormCondition<M>? = nil, control: ConfigFormControl<M> = .automatic
	) {
		let make: (Binding<M>) -> Binding<Double> = { m in
			Binding(get: { Double(m.wrappedValue[keyPath: field.keyPath]) },
					set: { m.wrappedValue[keyPath: field.keyPath] = Float($0) })
		}
		self.init(
			erasing: field, value: .float(make), symbol: symbol, shownWhen: shownWhen, enabledWhen: enabledWhen,
			control: control, byteCap: nil, inverted: false, enumOrder: nil, enumValues: nil, displayDefault: nil
		)
	}

	init(
		_ field: ConfigField<M, String>, symbol: String? = nil, shownWhen: ConfigFormCondition<M>? = nil,
		enabledWhen: ConfigFormCondition<M>? = nil, control: ConfigFormControl<M> = .automatic, byteCap: Int? = nil
	) {
		self.init(
			erasing: field, value: .string { $0[dynamicMember: field.keyPath] }, symbol: symbol, shownWhen: shownWhen,
			enabledWhen: enabledWhen, control: control, byteCap: byteCap, inverted: false,
			enumOrder: nil, enumValues: nil, displayDefault: nil
		)
	}

	init<E: SwiftProtobuf.Enum & CaseIterable>(
		_ field: ConfigField<M, E>, symbol: String? = nil,
		shownWhen: ConfigFormCondition<M>? = nil, enabledWhen: ConfigFormCondition<M>? = nil,
		control: ConfigFormControl<M> = .automatic, enumOrder: [Int]? = nil,
		enumValues: ((ConfigFormEnvironment) -> [Int])? = nil
	) {
		let make: (Binding<M>) -> Binding<Int> = { m in
			Binding(get: { m.wrappedValue[keyPath: field.keyPath].rawValue },
					set: { if let e = E(rawValue: $0) { m.wrappedValue[keyPath: field.keyPath] = e } })
		}
		let cases = E.allCases.map(\.rawValue)
		let caseName: (Int) -> String = { raw in E(rawValue: raw).map { "\($0)" } ?? "\(raw)" }
		self.init(
			erasing: field, value: .enumeration(make, cases: cases, caseName: caseName), symbol: symbol,
			shownWhen: shownWhen, enabledWhen: enabledWhen, control: control, byteCap: nil, inverted: false,
			enumOrder: enumOrder, enumValues: enumValues, displayDefault: nil
		)
	}

	/// Anything else - a nested message, bytes, a 64-bit field. Only `.custom` renders it.
	init<V>(
		unsupported field: ConfigField<M, V>, control: ConfigFormControl<M>, symbol: String? = nil,
		shownWhen: ConfigFormCondition<M>? = nil, enabledWhen: ConfigFormCondition<M>? = nil
	) {
		self.init(
			erasing: field, value: .unsupported, symbol: symbol, shownWhen: shownWhen, enabledWhen: enabledWhen,
			control: control, byteCap: nil, inverted: false, enumOrder: nil, enumValues: nil, displayDefault: nil
		)
	}
}

/// A field left out on purpose, with the reason stated where the test can read it.
struct ConfigFormOmission<M: ConfigSchemaMessage> {
	let tag: Int
	let name: String
	let identity: FieldIdentity
	let reason: String
	/// The field whose control also writes this one, when a screen folds several fields
	/// into one row - a colour picker writing red, green and blue. A search result for
	/// the folded-away field then lands on the control that sets it.
	let coveredBy: FieldIdentity?

	init<V>(_ field: ConfigField<M, V>, _ reason: String, coveredBy: FieldIdentity? = nil) {
		tag = field.tag
		name = field.name
		identity = field.identity
		self.reason = reason
		self.coveredBy = coveredBy
	}

	/// For fields the schema marks unsupported, which have no typed descriptor.
	init(_ field: AnyConfigField<M>, _ reason: String, coveredBy: FieldIdentity? = nil) {
		tag = field.tag
		name = field.name
		identity = field.identity
		self.reason = reason
		self.coveredBy = coveredBy
	}
}

/// What the app knows at render time that the schema does not.
struct ConfigFormEnvironment {
	let node: NodeInfoEntity?
	/// A radio is connected at all.
	let isConnected: Bool
	/// The node being configured is the connected radio, not a remote admin target.
	let isConnectedNode: Bool
	let isDIYHardware: Bool
	let hasWifi: Bool
	let hasEthernet: Bool
	let hasXeddsa: Bool
	let firmwareAtLeast: (String) -> Bool
}

/// A yes/no about the message or the environment, built from typed fields so a renamed
/// field fails to compile. Evaluated per render; nothing is cached.
struct ConfigFormCondition<M: ConfigSchemaMessage> {
	let evaluate: (M, ConfigFormEnvironment) -> Bool
	/// True when the condition reads the environment rather than the message. Counted by
	/// the tests so escape hatches are added deliberately.
	let isEnvironmental: Bool

	private init(environmental: Bool = false, _ evaluate: @escaping (M, ConfigFormEnvironment) -> Bool) {
		self.evaluate = evaluate
		isEnvironmental = environmental
	}

	static func isTrue(_ f: ConfigField<M, Bool>) -> Self { .init { m, _ in m[keyPath: f.keyPath] } }
	static func isFalse(_ f: ConfigField<M, Bool>) -> Self { .init { m, _ in !m[keyPath: f.keyPath] } }
	static func equals<V: Equatable>(_ f: ConfigField<M, V>, _ value: V) -> Self {
		.init { m, _ in m[keyPath: f.keyPath] == value }
	}
	static func nonZero<V: BinaryInteger>(_ f: ConfigField<M, V>) -> Self { .init { m, _ in m[keyPath: f.keyPath] != 0 } }
	/// A predicate over one field's value, for what `equals` cannot say - "the address
	/// names the public server".
	static func satisfies<V>(_ f: ConfigField<M, V>, _ predicate: @escaping (V) -> Bool) -> Self {
		.init { m, _ in predicate(m[keyPath: f.keyPath]) }
	}
	static func flag<V: BinaryInteger>(_ f: ConfigField<M, V>, _ bit: V) -> Self {
		.init { m, _ in m[keyPath: f.keyPath] & bit != 0 }
	}
	static func all(_ conditions: [Self]) -> Self {
		.init(environmental: conditions.contains { $0.isEnvironmental }) { m, e in conditions.allSatisfy { $0.evaluate(m, e) } }
	}
	static func any(_ conditions: [Self]) -> Self {
		.init(environmental: conditions.contains { $0.isEnvironmental }) { m, e in conditions.contains { $0.evaluate(m, e) } }
	}
	static func not(_ condition: Self) -> Self {
		.init(environmental: condition.isEnvironmental) { m, e in !condition.evaluate(m, e) }
	}

	// The environment gates the census found: firmware version and hardware capability.
	static func firmware(atLeast version: String) -> Self { .init(environmental: true) { _, e in e.firmwareAtLeast(version) } }
	static var hasWifi: Self { .init(environmental: true) { _, e in e.hasWifi } }
	static var hasEthernet: Self { .init(environmental: true) { _, e in e.hasEthernet } }
	static var hasXeddsa: Self { .init(environmental: true) { _, e in e.hasXeddsa } }
	static var isConnectedNode: Self { .init(environmental: true) { _, e in e.isConnectedNode } }
	/// Anything else. Counted by the tests, so use it knowingly.
	static func environment(_ predicate: @escaping (ConfigFormEnvironment) -> Bool) -> Self {
		.init(environmental: true) { _, e in predicate(e) }
	}
}

/// One option of a fixed list a screen shows for an integer field: hops 0-7, the
/// store-and-forward record counts, and so on.
struct ConfigFormOption: Identifiable, Hashable {
	let value: Int
	let title: String
	var id: Int { value }
}

/// One bit of a flags field, shown as its own toggle. The label comes from the flag's
/// enum value metadata; only the pairing of field to enum is stated here.
struct ConfigFormFlag<M: ConfigSchemaMessage> {
	let rawValue: Int
	let label: () -> String?
	var symbol: String?
	var shownWhen: ConfigFormCondition<M>?

	init(rawValue: Int, label: @escaping () -> String?, symbol: String? = nil, shownWhen: ConfigFormCondition<M>? = nil) {
		self.rawValue = rawValue
		self.label = label
		self.symbol = symbol
		self.shownWhen = shownWhen
	}
}

/// Which control renders a field. `.automatic` picks from the field's kind and metadata.
enum ConfigFormControl<M: ConfigSchemaMessage> {
	case automatic
	/// `UpdateIntervalPicker` over a seconds field, with the curated option set.
	case interval(IntervalConfiguration)
	/// The 0-48 GPIO picker with "Unset" for zero.
	case gpioPin
	/// A fixed option list for an integer field.
	case options([ConfigFormOption])
	/// Needs `min_value` and `max_value` in the registry; falls back to `.automatic`.
	case slider(step: Double)
	case stepper
	/// An enum shown as a segmented picker.
	case segmented
	/// A string shown masked, through `SecureInput`.
	case secure
	/// "Zero means off": a toggle, and the value control beneath it while on. `onValue`
	/// is what switching on writes; `then` renders the value - `.automatic`, an interval,
	/// an option list, a stepper or a slider.
	indirect case nonZeroToggle(onValue: UInt32, then: ConfigFormControl<M> = .automatic)
	/// A bitfield, one toggle per listed bit.
	case flags([ConfigFormFlag<M>])
	/// Anything else. Counted by the tests, so use it knowingly.
	case custom((Binding<M>) -> AnyView)

	var isCustom: Bool {
		if case .custom = self { return true }
		return false
	}
}

// MARK: - Validation

/// The checks `ConfigFormOverlayTests` runs over every migrated screen, type-erased so
/// the overlays of different messages can sit in one list.
protocol AnyConfigFormOverlay {
	var protoName: String { get }
	/// The row a search result names, or nil when this screen does not lay it out.
	func rowID(for identity: FieldIdentity) -> String?
	/// Whether this screen leaves the field out on purpose.
	func omits(_ identity: FieldIdentity) -> Bool
	/// What is wrong with the overlay, as sentences; empty when nothing is.
	func problems() -> [String]
	/// Escape hatches in use, pinned by the tests so a new one is added on purpose.
	var customControlCount: Int { get }
	var environmentConditionCount: Int { get }
}

extension ConfigFormOverlay: AnyConfigFormOverlay {
	var protoName: String { M.protoName }

	private var laidOut: [ConfigFormField<M>] { sections.flatMap(\.fields) }

	var customControlCount: Int { laidOut.filter { $0.control.isCustom }.count }

	var environmentConditionCount: Int {
		let sectionConditions = sections.compactMap(\.shownWhen) + sections.compactMap(\.enabledWhen)
		let fieldConditions = laidOut.flatMap { [$0.shownWhen, $0.enabledWhen].compactMap { $0 } }
		return (sectionConditions + fieldConditions).filter(\.isEnvironmental).count
	}

	func problems() -> [String] {
		var out: [String] = []
		let fields = laidOut
		let names = fields.map(\.field.name)
		for section in sections where section.fields.isEmpty {
			out.append("section \(section.title ?? "(untitled)") has no fields")
		}
		for name in Set(names) where names.filter({ $0 == name }).count > 1 {
			out.append("\(name) is laid out more than once")
		}
		for omission in omitted where names.contains(omission.name) {
			out.append("\(omission.name) is both laid out and omitted")
		}

		// Every field a form could render is either laid out or omitted with a reason.
		// A nested message is covered by its flattened children, and a deprecated field
		// with no label has nothing to render. Names, not tags: see `id`.
		let accounted = Set(names + omitted.map(\.name))
		for field in M.allFields where field.unsupportedReason == nil && field.kind != .message && !field.name.contains(".") {
			if field.isDeprecated, field.metadata?.label == nil { continue }
			if !accounted.contains(field.name) {
				out.append("\(field.name) (tag \(field.tag)) is neither laid out nor omitted")
			}
		}

		for f in fields {
			let name = f.field.name
			// A custom control brings its own text; everything else reads the registry.
			if f.field.metadata?.label == nil, !f.control.isCustom {
				out.append("\(name) has no label in the registry; annotate it upstream before laying it out")
			}
			if f.byteCap != nil, f.field.kind != .string { out.append("\(name): byteCap on a non-string field") }
			if f.inverted, f.field.kind != .bool { out.append("\(name): inverted on a non-Bool field") }
			if f.enumOrder != nil || f.enumValues != nil, f.field.kind != .enumeration {
				out.append("\(name): enum options on a non-enum field")
			}
			if case .unsupported = f.value, !f.control.isCustom {
				out.append("\(name) is \(f.field.kind) and needs a custom control")
			}
			out += Self.problems(with: f.control, on: f, name: name)
			if case .nonZeroToggle(_, let inner) = f.control {
				switch inner {
				case .automatic, .interval, .options, .stepper, .slider:
					out += Self.problems(with: inner, on: f, name: name)
				default:
					out.append("\(name): the control inside a non-zero toggle must be automatic, an interval, an option list, a stepper or a slider")
				}
			}
		}
		return out
	}

	private static func problems(with control: ConfigFormControl<M>, on f: ConfigFormField<M>, name: String) -> [String] {
		switch control {
		case .interval, .gpioPin, .options, .nonZeroToggle, .flags:
			if !(f.field.kind == .uint32 || f.field.kind == .int32) { return ["\(name): integer control on \(f.field.kind)"] }
		case .slider, .stepper:
			if f.field.metadata?.minValue == nil || f.field.metadata?.maxValue == nil {
				return ["\(name): slider/stepper without min_value and max_value in the registry"]
			}
		case .secure:
			if f.field.kind != .string { return ["\(name): secure on a non-string field"] }
		case .segmented:
			if f.field.kind != .enumeration { return ["\(name): segmented on a non-enum field"] }
		case .automatic, .custom:
			break
		}
		return []
	}
}
