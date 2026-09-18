//
//  SettingsSearchIndexTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/13/26.
//
import Foundation
import Testing
@testable import Meshtastic

/// Guards that turn index drift into a test failure rather than a wrong result.
///
/// A catalogue of this size rots silently: a control is renamed, a field is added,
/// and search keeps pointing at something that no longer exists. Nothing about a
/// stale entry is visibly broken, which is why these exist.
@Suite("Settings search index")
struct SettingsSearchIndexTests {

	// MARK: - Repository access

	/// The repo root, walked up from this file. The simulator can usually read host
	/// paths, but when it cannot these tests skip rather than fail — they guard the
	/// source tree, not the built product.
	private static var repoRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}

	private static func proto(_ name: String) -> String? {
		let url = repoRoot.appendingPathComponent("protobufs/meshtastic/\(name).proto")
		return try? String(contentsOf: url, encoding: .utf8)
	}

	// MARK: - Completeness

	/// Fields that carry no label on purpose. Each must name which group it is in,
	/// so "the extractor could not find one" cannot quietly join the list.
	///
	/// Spec 019 FR-015a. Two groups only:
	///   - no control at all, whether saved-but-unexposed or not user-facing
	///   - a label the app renders from a value rather than a literal
	static let exemptFields: [String: String] = [
		"ls_secs": "no control - saved but never exposed",
		"min_wake_secs": "no control - saved but never exposed",
		"wait_bluetooth_secs": "no control - saved but never exposed",
		"sds_secs": "no control - saved but never exposed",
		"private_key": "no user interface",
		"admin_key": "no user interface",
		"public_key": "no user interface",
		"broadcast_targets": "no user interface",
		"ipv4_config": "no user interface - nested message",
		"position_flags": "labels live on the PositionFlags enum values",
		"packet_signature_policy": "no control",
		"override_console_serial_port": "no control",
		"broadcast_offer_channel": "no control",
		"broadcast_offer_preset": "no control",
		"broadcast_offer_region": "no control",
		"flags": "no control",
		"gps_mode": "segmented picker with no literal label",
		"position_precision": "slider with no literal label",

		// Firmware fields this client does not offer yet. Not oversights in the
		// annotations - there is no control to label, because the setting is not
		// surfaced. Each should leave this list when the app grows a control for it,
		// which is exactly the prompt this list is meant to give.
		"buzzer_mode": "no control - not yet offered by this client",
		"ipv6_enabled": "no control - not yet offered by this client",
		"use_long_node_name": "no control - not yet offered by this client",
		"enable_message_bubbles": "no control - not yet offered by this client",
		"clear_on_reboot": "no control - not yet offered by this client",
		"health_measurement_enabled": "no control - not yet offered by this client",
		"health_update_interval": "no control - not yet offered by this client",
		"health_screen_enabled": "no control - not yet offered by this client",
		"air_quality_screen_enabled": "no control - not yet offered by this client",
		"admin_channel_enabled": "no control - not yet offered by this client",
		"device_battery_ina_address": "no control - not yet offered by this client",
		"powermon_enables": "no control - diagnostics, not a user setting",

		// Written by the app but never presented: no control exists to label.
		"frequency_offset": "no control - written but never edited",
		"override_duty_cycle": "no control - written but never edited",
		"pa_fan_disabled": "no control - written but never edited",
		"ignore_incoming": "no control - repeated field, no UI",
		"fem_lna_mode": "no control - written but never edited",
		"serial_hal_only": "no control - written but never edited",
		"map_report_settings": "nested message; its own fields are indexed separately"
	]

	@Test("Every configuration field is indexed or exempted with a stated reason")
	func everyFieldIsAccountedFor() throws {
		let config = Self.proto("config")
		let module = Self.proto("module_config")
		guard let config, let module else {
			// On CI this must fail: unit-tests.yml checks out submodules precisely so
			// this test has something to read, and a silent skip there would let the
			// whole guard pass for the wrong reason. Locally the simulator sometimes
			// cannot see host paths, and skipping is the right call.
			if ProcessInfo.processInfo.environment["CI"] != nil {
				Issue.record("protobufs/meshtastic/*.proto unreadable on CI — is the submodule checked out?")
			}
			return
		}

		let indexedTags = Set(
			SettingsSearchIndex.entries.compactMap { entry -> String? in
				guard let field = entry.field else { return nil }
				return "\(field.messageName)#\(field.tag)"
			}
		)

		var unaccounted: [String] = []
		for (source, text) in [("config", config), ("module_config", module)] {
			for (message, field, tag) in Self.fields(in: text) {
				// Only messages that map to a settings screen are in scope; the rest
				// have no UI to search for.
				guard SettingsSearchIndex.screens[message] != nil else { continue }
				if indexedTags.contains("\(message)#\(tag)") { continue }
				if Self.exemptFields[field] != nil { continue }
				// Deprecated fields are NOT excluded. They are shown marked rather than
				// hidden, so one carrying a label still needs an entry; only an
				// unlabelled deprecated field is genuinely unsearchable.
				if let meta = FieldMetadataRegistry.get(message, tag: tag),
				   meta.deprecated == true, meta.label == nil { continue }
				unaccounted.append("\(source): \(message).\(field) (tag \(tag))")
			}
		}

		#expect(
			unaccounted.isEmpty,
			"""
			\(unaccounted.count) configuration field(s) are neither indexed nor exempt. \
			Annotate them upstream, or add them to exemptFields naming which group they \
			belong to. "The seeder could not find a label" is not one of the groups - a \
			control in a nested view or behind a computed binding still has a label.
			\(unaccounted.sorted().joined(separator: "\n"))
			"""
		)
	}

	/// `(message full name, field name, tag)` for every field, skipping nested
	/// message and enum bodies so only each message's own fields are seen.
	static func fields(in text: String) -> [(String, String, Int)] {
		var stripped = text.replacingOccurrences(
			of: "/\\*.*?\\*/", with: "", options: .regularExpression)
		stripped = stripped.replacingOccurrences(
			of: "//[^\n]*", with: "", options: .regularExpression)

		var out: [(String, String, Int)] = []
		func walk(_ body: String, prefix: String) {
			var masked = Array(body)
			let blocks = try? NSRegularExpression(pattern: "\\b(message|enum)\\s+(\\w+)\\s*\\{")
			let ns = body as NSString
			blocks?.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
				guard let m, let open = body.range(of: "{", range: Range(m.range, in: body)!.lowerBound..<body.endIndex)
				else { return }
				var depth = 1
				var idx = body.index(after: open.lowerBound)
				while idx < body.endIndex, depth > 0 {
					if body[idx] == "{" { depth += 1 } else if body[idx] == "}" { depth -= 1 }
					idx = body.index(after: idx)
				}
				let start = body.distance(from: body.startIndex, to: Range(m.range, in: body)!.lowerBound)
				// Matches are enumerated over the unmasked body, so a message nested two deep
				// shows up here as well as inside its parent's walk. Its start is already
				// masked by the parent's block, which is how to tell.
				guard start < masked.count, masked[start] != " " else { return }
				let end = body.distance(from: body.startIndex, to: idx)
				let kind = ns.substring(with: m.range(at: 1))
				let name = ns.substring(with: m.range(at: 2))
				for k in start..<min(end, masked.count) where masked[k] != "\n" { masked[k] = " " }
				if kind == "message" {
					let inner = String(body[body.index(after: open.lowerBound)..<body.index(before: idx)])
					walk(inner, prefix: "\(prefix).\(name)")
				}
			}
			let own = String(masked)
			let field = try? NSRegularExpression(
				pattern: "(?:optional\\s+|repeated\\s+)?[\\w.]+\\s+(\\w+)\\s*=\\s*(\\d+)\\s*[;\\[]")
			let ownNS = own as NSString
			field?.enumerateMatches(in: own, range: NSRange(location: 0, length: ownNS.length)) { m, _, _ in
				guard let m else { return }
				out.append((prefix, ownNS.substring(with: m.range(at: 1)),
							Int(ownNS.substring(with: m.range(at: 2))) ?? 0))
			}
		}

		let top = try? NSRegularExpression(pattern: "^message\\s+(\\w+)\\s*\\{", options: .anchorsMatchLines)
		let ns = stripped as NSString
		top?.enumerateMatches(in: stripped, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
			guard let m, let r = Range(m.range, in: stripped),
				  let open = stripped.range(of: "{", range: r.lowerBound..<stripped.endIndex) else { return }
			var depth = 1
			var idx = stripped.index(after: open.lowerBound)
			while idx < stripped.endIndex, depth > 0 {
				if stripped[idx] == "{" { depth += 1 } else if stripped[idx] == "}" { depth -= 1 }
				idx = stripped.index(after: idx)
			}
			let inner = String(stripped[stripped.index(after: open.lowerBound)..<stripped.index(before: idx)])
			walk(inner, prefix: "meshtastic.\(ns.substring(with: m.range(at: 1)))")
		}
		return out
	}

	// MARK: - Structural guards

	@Test("Every indexed destination is a real settings destination")
	func destinationsExist() throws {
		let known = Set(SettingsNavigationState.allCases)
		for entry in SettingsSearchIndex.entries {
			#expect(known.contains(entry.destination), "\(entry.id) names an unknown destination")
		}
	}

	@Test("No entry is blank, and none collides with another on the same screen")
	func entriesAreDistinctAndLabelled() throws {
		var seen = Set<String>()
		for entry in SettingsSearchIndex.entries {
			#expect(!entry.label.isEmpty, "\(entry.id) has an empty label")
			#expect(
				entry.label.trimmingCharacters(in: .whitespaces) == entry.label,
				"\(entry.id) has padded whitespace in its label")
			// Identity is destination plus label. Two entries sharing both are
			// indistinguishable in results, which is the bug this catches.
			#expect(seen.insert(entry.id).inserted, "duplicate entry: \(entry.id)")
		}
	}

	@Test("Registry-backed labels come through localized, not as raw catalog keys")
	func labelsAreResolved() throws {
		for entry in SettingsSearchIndex.entries where entry.field != nil {
			#expect(
				!entry.label.hasPrefix("meshtastic."),
				"\(entry.id) shows its catalog key, so the string never resolved")
		}
	}

	@Test("Per-screen entry counts are pinned")
	func perScreenCounts() throws {
		// A control added to a form without an index entry is otherwise invisible:
		// nothing fails, it is just unsearchable. Update these deliberately.
		let expected: [SettingsNavigationState: Int] = [
			.lora: 14,
			.bluetooth: 3,
			.security: 3
		]
		for (destination, count) in expected {
			let actual = SettingsSearchIndex.entries.filter { $0.destination == destination }.count
			#expect(
				actual == count,
				"""
				\(destination.rawValue) has \(actual) indexed controls, expected \(count). \
				If a setting was added or annotated, update this number deliberately.
				""")
		}
	}
}

/// Keeps the generated app-level catalogue honest.
///
/// The protobuf half cannot drift, because it is generated from the schema. This
/// half is generated from the views, and staleness is caught by
/// `.github/workflows/settings-catalogue-drift.yml` rather than here — these tests
/// run in the simulator, which has no way to shell out to the generator.
@Suite("Settings search catalogue")
struct SettingsSearchCatalogueTests {

	@Test("Curated entries carry no proto field, and app preferences work offline")
	func curatedEntriesAreShapedCorrectly() throws {
		for entry in SettingsSearchCatalogue.entries {
			#expect(
				entry.field == nil,
				"\(entry.id) has a proto field; it belongs in the registry half")
		}

		// Not every curated entry is offline-capable. Channels, the QR code, the user
		// record and the TAK server read the connected node. The app preferences do
		// not, and dimming those would be wrong - being findable with no radio is
		// most of why they are indexed.
		let offlineScreens: Set<SettingsNavigationState> = [
			.appSettings, .about, .routes, .routeRecorder, .appFiles,
			.localMeshDiscovery, .firmwareUpdates, .helpDocs,
			.debugLogs, .traceRoutes, .backupManagement, .coreDataBrowser,
			.deviceLinks, .tools
		]
		for entry in SettingsSearchCatalogue.entries where offlineScreens.contains(entry.destination) {
			#expect(!entry.requiresConnection, "\(entry.id) is an app preference and should not require a radio")
		}
	}

	@Test("Every app-level row on the Settings screen is indexed")
	func everyAppLevelScreenIsReachable() throws {
		// The rows that are not backed by a config message. Each one is a screen a
		// user can open from Settings, so each one must be findable by its name -
		// this is the half that does not come from the schema, so nothing else
		// catches it going missing.
		let expected: Set<SettingsNavigationState> = [
			.about, .helpDocs, .appSettings, .localMeshDiscovery, .routes,
			.routeRecorder, .firmwareUpdates, .channels, .shareQRCode, .user,
			.tak, .ringtone, .debugLogs, .traceRoutes, .backupManagement,
			.coreDataBrowser, .deviceLinks, .appFiles, .tools
		]
		let indexed = Set(SettingsSearchCatalogue.entries.map(\.destination))
		#expect(
			expected.subtracting(indexed).isEmpty,
			"not indexed: \(expected.subtracting(indexed).map(\.rawValue).sorted())")
	}

	@Test("A screen sits in the section it occupies on the Settings list")
	func sectionsMatchTheSettingsScreen() throws {
		// The breadcrumb is only useful if it names the group the user would have
		// scrolled to, so these pin a representative row per section.
		let expected: [SettingsNavigationState: SettingsListSection] = [
			.localMeshDiscovery: .general, .about: .general, .firmwareUpdates: .general,
			.channels: .radioConfiguration, .user: .deviceConfiguration,
			.ringtone: .configure, .debugLogs: .logging, .tools: .developers
		]
		for (destination, section) in expected {
			let entry = SettingsSearchCatalogue.entries.first { $0.destination == destination }
			let found = try #require(entry, "\(destination.rawValue) is not in the catalogue")
			#expect(found.listSection == section, "\(destination.rawValue) is in \(found.listSection)")
		}
	}

	@Test("Developers screens are hidden on a build that does not show them")
	func developerScreensAreBuildGated() throws {
		let developerScreens: Set<SettingsNavigationState> = [
			.backupManagement, .coreDataBrowser, .deviceLinks, .appFiles, .tools
		]
		for entry in SettingsSearchCatalogue.entries where developerScreens.contains(entry.destination) {
			#expect(entry.requiresDeveloperBuild, "\(entry.id) is in the Developers section")
		}

		// App Store builds do not render the Developers section at all, so a result
		// pointing into it would be an offer the user cannot take up.
		let release = SettingsSearchEngine.Availability(
			isConnected: true, isDIYHardware: false, isManaged: false,
			showsDeveloperSettings: false)
		#expect(
			SettingsSearchEngine.search("Data Browser", in: SettingsSearchCatalogue.entries, availability: release).isEmpty,
			"a Developers screen surfaced on a release build")

		let testflight = SettingsSearchEngine.Availability(
			isConnected: true, isDIYHardware: false, isManaged: false,
			showsDeveloperSettings: true)
		#expect(
			!SettingsSearchEngine.search("Data Browser", in: SettingsSearchCatalogue.entries, availability: testflight).isEmpty,
			"a Developers screen should be findable where the section renders")
	}

	@Test("Searching the discovery screen by name finds it")
	func localMeshDiscoveryIsFindable() throws {
		let available = SettingsSearchEngine.Availability(
			isConnected: false, isDIYHardware: false, isManaged: false)
		for query in ["Local Mesh", "discovery", "bonjour"] {
			let results = SettingsSearchEngine.search(
				query, in: SettingsSearchIndex.entries, availability: available)
			#expect(
				results.prefix(5).contains { $0.entry.destination == .localMeshDiscovery },
				"\"\(query)\" did not surface Local Mesh Discovery; got \(results.prefix(5).map(\.entry.label))")
		}
	}
}
