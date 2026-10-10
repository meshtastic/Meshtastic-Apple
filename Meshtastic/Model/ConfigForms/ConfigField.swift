//
//  ConfigField.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import Foundation
import MeshtasticProtobufs
import SwiftProtobuf

/// A configuration message with a generated field schema.
///
/// Conformances are generated into `ConfigFormSchema.swift` by
/// `scripts/protoc-gen-configform-swift`; nothing conforms by hand. The schema is the
/// structural half of a form - which fields exist, their tags, kinds and key paths.
/// Everything a user reads (label, description, unit, bounds) is looked up at runtime
/// through `FieldMetadataRegistry`, so the schema never carries display text.
protocol ConfigSchemaMessage: SwiftProtobuf.Message, Equatable {
	/// Full proto name, e.g. `meshtastic.ModuleConfig.SerialConfig`.
	static var protoName: String { get }
	/// Every field, in declaration order, including the ones a form cannot render.
	static var allFields: [AnyConfigField<Self>] { get }
}

extension ConfigSchemaMessage {
	/// A type-erased view, for walking every message in `ConfigFormSchema.all`.
	static var fieldSummaries: [ConfigFieldSummary] {
		allFields.map { ConfigFieldSummary(tag: $0.tag, name: $0.name, kind: $0.kind, isDeprecated: $0.isDeprecated) }
	}
}

/// What kind of value a field holds, which decides the control a form offers for it.
enum ConfigFieldKind: String {
	case bool, int32, uint32, int64, uint64, float, double, string, bytes, enumeration, message
	/// Repeated and map fields. A form renders these only through a custom control.
	case repeated
	/// A member of a `oneof`. None of the configuration messages use one today.
	case oneof
}

/// One field of `M`, typed by its value, with a key path a form can bind to.
///
/// `name` is the proto name, dotted when the field was flattened out of a singular
/// nested message (`map_report_settings.position_precision`). `identity` names the
/// message the tag actually belongs to - the nested one, in that case - because that
/// is how the registry is keyed.
struct ConfigField<M: ConfigSchemaMessage, V> {
	let tag: Int
	let name: String
	let keyPath: WritableKeyPath<M, V>
	let identity: FieldIdentity

	init(tag: Int, name: String, keyPath: WritableKeyPath<M, V>, identity: FieldIdentity) {
		self.tag = tag
		self.name = name
		self.keyPath = keyPath
		self.identity = identity
	}

	/// The field's metadata, or nil if the schema says nothing about it.
	var metadata: FieldMetadata? { identity.metadata }
}

/// A field with its value type erased, so a message's fields can sit in one array.
struct AnyConfigField<M: ConfigSchemaMessage> {
	let tag: Int
	let name: String
	let kind: ConfigFieldKind
	let identity: FieldIdentity
	/// For `.enumeration`: the enum's proto name, for looking up option labels.
	let enumTypeName: String?
	let isDeprecated: Bool
	/// Why a form cannot render this field directly; nil for every supported kind.
	let unsupportedReason: String?

	init<V>(_ field: ConfigField<M, V>, kind: ConfigFieldKind, enumTypeName: String? = nil, isDeprecated: Bool = false) {
		tag = field.tag
		name = field.name
		self.kind = kind
		identity = field.identity
		self.enumTypeName = enumTypeName
		self.isDeprecated = isDeprecated
		unsupportedReason = nil
	}

	private init(tag: Int, name: String, kind: ConfigFieldKind, identity: FieldIdentity, reason: String, isDeprecated: Bool) {
		self.tag = tag
		self.name = name
		self.kind = kind
		self.identity = identity
		enumTypeName = nil
		self.isDeprecated = isDeprecated
		unsupportedReason = reason
	}

	/// A field the generator saw but a form cannot bind: repeated, map or oneof.
	static func unsupported(tag: Int, name: String, kind: ConfigFieldKind, identity: FieldIdentity,
							reason: String, isDeprecated: Bool) -> AnyConfigField<M> {
		AnyConfigField(tag: tag, name: name, kind: kind, identity: identity, reason: reason, isDeprecated: isDeprecated)
	}

	var metadata: FieldMetadata? { identity.metadata }
}

/// One message's name and field shapes, for tests that walk every message. A plain
/// value rather than a metatype: calling static members through
/// `any ConfigSchemaMessage.Type` sends the compiler into an existential opening it
/// does not always survive.
struct ConfigMessageDescriptor {
	let protoName: String
	let fields: [ConfigFieldSummary]
}

/// The type-erased shape of one field, for tests that walk every message.
struct ConfigFieldSummary: Hashable {
	let tag: Int
	let name: String
	let kind: ConfigFieldKind
	let isDeprecated: Bool
}
