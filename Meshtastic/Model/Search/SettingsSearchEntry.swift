//
//  SettingsSearchEntry.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/13/26.
//
import Foundation

/// One indexed control under Settings.
///
/// One control, one entry. A bitfield field such as `position_flags` therefore
/// contributes ten entries that share a `field`, and a field with no control
/// contributes none.
struct SettingsSearchEntry: Identifiable, Hashable {
	/// Where tapping the result goes.
	let destination: SettingsNavigationState
	/// The screen's own title, localized — "LoRa".
	let screenTitle: String
	/// The section within that screen, localized.
	let sectionTitle: String?
	/// Which group of the Settings list the row sits in.
	let listSection: SettingsListSection
	/// What the control says on screen, localized.
	let label: String
	/// The control's explanatory text, localized. Most entries have none.
	let subtitle: String?
	/// Localized synonyms. Usually empty: a setting whose label already says what
	/// it is does not need synonyms invented for it, and ranking weights a keyword
	/// hit below a label hit, so a sparse set costs nothing.
	let keywords: [String]
	/// The protobuf field this describes, or nil for app-level settings.
	let field: FieldIdentity?
	/// Radio configuration is unavailable without a connected radio.
	let requiresConnection: Bool
	/// The Developers section only renders in debug and TestFlight builds, so its
	/// screens must not surface in search on an App Store build.
	let requiresDeveloperBuild: Bool

	/// Destination plus label, never label alone: "Enabled" is the label of six
	/// different controls, so the screen is part of an entry's identity.
	var id: String { "\(destination.rawValue)#\(label)" }

	init(
		destination: SettingsNavigationState,
		screenTitle: String,
		sectionTitle: String? = nil,
		listSection: SettingsListSection,
		label: String,
		subtitle: String? = nil,
		keywords: [String] = [],
		field: FieldIdentity? = nil,
		requiresConnection: Bool = true,
		requiresDeveloperBuild: Bool = false
	) {
		self.destination = destination
		self.screenTitle = screenTitle
		self.sectionTitle = sectionTitle
		self.listSection = listSection
		self.label = label
		self.subtitle = subtitle
		self.keywords = keywords
		self.field = field
		self.requiresConnection = requiresConnection
		self.requiresDeveloperBuild = requiresDeveloperBuild
	}
}

/// A protobuf field, named the way the generated registry names it.
///
/// Tag, not Swift property name: a field's spelling differs across its proto,
/// generated, entity and view-state forms — `sx126x_rx_boosted_gain` is
/// `sx126XRxBoostedGain` is `rxBoostedGain` — and only the tag is stable by
/// contract.
struct FieldIdentity: Hashable {
	/// Full proto name, e.g. `meshtastic.Config.LoRaConfig`.
	let messageName: String
	/// Proto field number.
	let tag: Int

	/// The registry entry for this field, or nil if it carries no annotation.
	/// Absence means "nothing was said", never "not deprecated".
	var metadata: FieldMetadata? { FieldMetadataRegistry.get(messageName, tag: tag) }
}

/// The three groupings `Settings.swift` already uses, so a result's breadcrumb
/// matches the list the user would otherwise have scrolled. Declaration order is
/// also the tiebreak order for equally-scored results.
enum SettingsListSection: Int, CaseIterable, Hashable {
	/// The unlabelled group at the top of Settings — About, Help, App Settings,
	/// Local Mesh Discovery, Routes, Route Recorder, Firmware Updates.
	case general
	case radioConfiguration
	case deviceConfiguration
	case configure
	case logging
	case developers

	var title: String {
		switch self {
		case .general:
			// No header on screen; results still need one to group under.
			return String(localized: "General", comment: "Settings list section")
		case .radioConfiguration:
			return String(localized: "Radio Configuration", comment: "Settings list section")
		case .deviceConfiguration:
			return String(localized: "Device Configuration", comment: "Settings list section")
		case .configure:
			return String(localized: "Configure", comment: "Settings list section")
		case .logging:
			return String(localized: "Logging", comment: "Settings list section")
		case .developers:
			return String(localized: "Developers", comment: "Settings list section")
		}
	}
}

/// Why a result is shown the way it is.
///
/// Computed per query from connection and node state, not baked into the index,
/// which stays static. One mechanism covers every reason a result is not plainly
/// available, so nothing disappears without a reason the row can state.
enum SettingsSearchVisibility: Hashable {
	case normal
	/// Shown, de-emphasised, with `reason` explaining why.
	case deEmphasised(reason: String)
	/// Not shown at all.
	case hidden
}

/// An entry plus what the match was worth. Produced per keystroke, never stored.
struct SettingsSearchResult: Identifiable, Hashable {
	let entry: SettingsSearchEntry
	let score: Int
	let visibility: SettingsSearchVisibility

	var id: String { entry.id }
}
