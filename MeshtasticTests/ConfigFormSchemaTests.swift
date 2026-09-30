//
//  ConfigFormSchemaTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import Foundation
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

/// Keeps the generated field schema honest against the protos it was generated from.
///
/// `ConfigFormSchema.swift` is written by `scripts/protoc-gen-configform-swift`
/// (gen_protos.sh, phase 5). A submodule bump without a regeneration would leave the
/// schema describing fields that moved or vanished; a wrong key path fails to compile,
/// but a missing field compiles fine and simply never renders. This is the guard for
/// that second case.
@Suite("Configuration form schema")
struct ConfigFormSchemaTests {

	private static var repoRoot: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
	}

	private static func proto(_ name: String) -> String? {
		try? String(contentsOf: repoRoot.appendingPathComponent("protobufs/meshtastic/\(name).proto"), encoding: .utf8)
	}

	/// The schema's view of a message: tag -> (name, kind), top level only.
	private static func schemaFields(for protoName: String) -> [Int: ConfigFieldSummary]? {
		guard let message = ConfigFormSchema.all.first(where: { $0.protoName == protoName }) else { return nil }
		return Dictionary(uniqueKeysWithValues: message.fields
			.filter { !$0.name.contains(".") }
			.map { ($0.tag, $0) })
	}

	@Test("Every field of every configuration message has a descriptor with the same tag and name")
	func everyFieldIsDescribed() throws {
		guard let config = Self.proto("config"), let module = Self.proto("module_config") else {
			if ProcessInfo.processInfo.environment["CI"] != nil {
				Issue.record("protobufs/meshtastic/*.proto unreadable on CI — is the submodule checked out?")
			}
			return
		}

		var missing: [String] = []
		var misnamed: [String] = []
		var seenMessages: Set<String> = []
		for text in [config, module] {
			for (message, field, tag) in SettingsSearchIndexTests.fields(in: text) {
				// Only messages nested under the two wrappers are configuration screens.
				guard message.hasPrefix("meshtastic.Config.") || message.hasPrefix("meshtastic.ModuleConfig.") else { continue }
				seenMessages.insert(message)
				guard let fields = Self.schemaFields(for: message) else {
					missing.append("\(message) (whole message)")
					continue
				}
				guard let described = fields[tag] else {
					missing.append("\(message).\(field) (tag \(tag))")
					continue
				}
				if described.name != field {
					misnamed.append("\(message) tag \(tag): schema says \(described.name), proto says \(field)")
				}
			}
		}
		let missingReport = missing.sorted().joined(separator: "\n")
		let misnamedReport = misnamed.joined(separator: "\n")
		#expect(missing.isEmpty, "not in the schema - rerun scripts/gen_protos.sh:\n\(missingReport)")
		#expect(misnamed.isEmpty, "\(misnamedReport)")
		// A message the walk never yielded has no fields in the proto (SessionkeyConfig is
		// empty today); the schema must agree, and must not describe anything else.
		let unexpected = ConfigFormSchema.all
			.filter { !seenMessages.contains($0.protoName) && !$0.fields.isEmpty }
			.map(\.protoName)
		#expect(unexpected.isEmpty, "schema describes fields for a message the proto does not have: \(unexpected)")
	}

	@Test("Tags are unique within a message")
	func shapeIsSound() throws {
		for message in ConfigFormSchema.all {
			let topLevel = message.fields.filter { !$0.name.contains(".") }
			let name = message.protoName
			#expect(Set(topLevel.map(\.tag)).count == topLevel.count, "\(name) repeats a tag")
		}
	}

	@Test("Singular nested messages are flattened one level")
	func nestedFieldsAreFlattened() throws {
		// MQTTConfig.map_report_settings is the case the MQTT screen needs; the flattened
		// descriptors carry the child's identity so the registry lookup finds them.
		let mqtt = ModuleConfig.MQTTConfig.allFields
		let nested = mqtt.filter { $0.name.hasPrefix("map_report_settings.") }
		#expect(nested.count == ModuleConfig.MapReportSettings.allFields.count)
		#expect(nested.allSatisfy { $0.identity.messageName == "meshtastic.ModuleConfig.MapReportSettings" })
		#expect(mqtt.contains { $0.name == "map_report_settings" && $0.kind == .message })
	}

	@Test("Repeated fields are present but marked unsupported, with a reason")
	func repeatedFieldsAreMarked() throws {
		let adminKey = Config.SecurityConfig.allFields.first { $0.name == "admin_key" }
		let found = try #require(adminKey)
		#expect(found.kind == .repeated)
		#expect(found.unsupportedReason != nil)
	}

	@Test("A key path reads and writes the field it names")
	func keyPathsBind() throws {
		var serial = ModuleConfig.SerialConfig()
		serial[keyPath: ModuleConfig.SerialConfig.Fields.txd.keyPath] = 21
		#expect(serial.txd == 21)
		var lora = Config.LoRaConfig()
		lora[keyPath: Config.LoRaConfig.Fields.sx126XRxBoostedGain.keyPath] = true
		#expect(lora.sx126XRxBoostedGain)
		var mqtt = ModuleConfig.MQTTConfig()
		mqtt[keyPath: ModuleConfig.MQTTConfig.Fields.mapReportSettings_positionPrecision.keyPath] = 14
		#expect(mqtt.mapReportSettings.positionPrecision == 14)
		#expect(mqtt.hasMapReportSettings, "writing through the flattened key path creates the sub-message")
	}

	@Test("Descriptors resolve their metadata through the registry")
	func metadataResolves() throws {
		let hops = Config.LoRaConfig.Fields.hopLimit
		#expect(hops.metadata?.label != nil, "hop_limit is annotated upstream; the identity must reach it")
		#expect(hops.identity == FieldIdentity(messageName: "meshtastic.Config.LoRaConfig", tag: 8))
	}
}
