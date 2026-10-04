//
//  ModuleAvailabilityTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import Testing
import MeshtasticProtobufs
@testable import Meshtastic

/// The two questions that decide whether a module's settings belong on a node's list:
/// whether the build left it out, and whether the firmware reads it at all.
@Suite("Module availability")
struct ModuleAvailabilityTests {

	/// The version comparison the settings list works from, shared with the node entity.
	@Test("A node that has never reported a version is offered everything")
	func unknownVersionIsPermissive() {
		#expect(NodeInfoEntity.firmware(nil, isAtLeast: "2.8.0"))
		#expect(NodeInfoEntity.firmware("", isAtLeast: "2.8.0"))
	}

	@Test("The comparison is numeric, not lexical")
	func comparisonIsNumeric() {
		// The trap this avoids: "2.7.9" sorts after "2.7.20" as text.
		#expect(NodeInfoEntity.firmware("2.7.20", isAtLeast: "2.7.9"))
		#expect(!NodeInfoEntity.firmware("2.7.9", isAtLeast: "2.7.20"))
		#expect(NodeInfoEntity.firmware("2.8.0", isAtLeast: "2.8.0"), "the release itself counts")
		#expect(!NodeInfoEntity.firmware("2.7.26", isAtLeast: "2.8.0"))
		// Firmware reports a build hash after the version; it must not change the answer.
		#expect(NodeInfoEntity.firmware("2.8.0.abc1234", isAtLeast: "2.8.0"))
	}

	@Test("The newest modules carry the firmware version the schema dates them to")
	func moduleVersionsComeFromTheSchema() throws {
		// The settings list reads these by tag rather than writing releases into the app,
		// so a wrong or missing annotation shows up here rather than on somebody's radio.
		let expected: [Int: String] = [
			14: "2.7.20",   // Status Message
			15: "2.8.0",    // Traffic Management
			16: "2.8.0",    // TAK
			17: "2.8.0"     // Mesh Beacon
		]
		for (tag, version) in expected {
			let metadata = try #require(FieldMetadataRegistry.get("meshtastic.ModuleConfig", tag: tag),
										"ModuleConfig tag \(tag) has no metadata")
			#expect(metadata.sinceFirmware == version, "ModuleConfig tag \(tag)")
		}
	}

	@Test("An older module states no version, so it stays offered")
	func olderModulesAreUnannotated() {
		// Tags 1-13 predate the annotations. They must read as permissive, or every
		// existing module row would vanish.
		for tag in 1...13 {
			let since = FieldMetadataRegistry.get("meshtastic.ModuleConfig", tag: tag)?.sinceFirmware
			#expect(since == nil, "ModuleConfig tag \(tag) gained a version; the gate needs a test")
		}
	}
}
