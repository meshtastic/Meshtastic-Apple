//
//  SettingsSearchCatalogue.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/13/26.
//
import Foundation

/// The settings that have no protobuf behind them, written out by hand.
///
/// Everything the radio stores comes from the schema through
/// `FieldMetadataRegistry`. These do not: they are app preferences, tools and
/// screens that exist only here, so there is nothing to generate from and the text
/// lives where a translator can reach it.
///
/// One file rather than a declaration beside each view, so that what is indexed can
/// be read in one place instead of assembled from twenty. Hand-written rather than
/// generated, because with no schema behind them a generated file would itself be
/// the source of truth and nothing would enforce regenerating it.
///
/// `requiresConnection` is false throughout: these work with no radio attached,
/// which is most of why they are worth finding while disconnected.
enum SettingsSearchCatalogue {

	static let entries: [SettingsSearchEntry] = appSettings + tools + channels

	// MARK: - App Settings

	private static let appSettings: [SettingsSearchEntry] = [
		.init(destination: .appSettings, screenTitle: screen, sectionTitle: sectionApp,
			  listSection: .configure,
			  label: String(localized: "Administration", comment: "App settings control"),
			  subtitle: String(localized: "Manage which nodes this app may configure remotely.",
							   comment: "App settings control"),
			  keywords: [String(localized: "admin", comment: "Search keyword")],
			  requiresConnection: false),
		.init(destination: .appSettings, screenTitle: screen, sectionTitle: sectionApp,
			  listSection: .configure,
			  label: String(localized: "Usage and Crash Data", comment: "App settings control"),
			  subtitle: String(localized: "Share anonymous diagnostics to help find crashes.",
							   comment: "App settings control"),
			  keywords: [String(localized: "analytics", comment: "Search keyword"),
						 String(localized: "telemetry", comment: "Search keyword"),
						 String(localized: "privacy", comment: "Search keyword")],
			  requiresConnection: false),
		.init(destination: .appSettings, screenTitle: screen, sectionTitle: sectionApp,
			  listSection: .configure,
			  label: String(localized: "Automatically Connect", comment: "App settings control"),
			  subtitle: String(localized: "Reconnect to the last radio when the app opens.",
							   comment: "App settings control"),
			  requiresConnection: false),
		.init(destination: .appSettings, screenTitle: screen, sectionTitle: sectionApp,
			  listSection: .configure,
			  label: String(localized: "App Icon", comment: "App settings control"),
			  keywords: [String(localized: "icon", comment: "Search keyword"),
						 String(localized: "appearance", comment: "Search keyword")],
			  requiresConnection: false),
		.init(destination: .appSettings, screenTitle: screen,
			  sectionTitle: String(localized: "Node Layout", comment: "App settings section"),
			  listSection: .configure,
			  label: String(localized: "Node List Density", comment: "App settings control"),
			  subtitle: String(localized: "How much detail each row of the node list shows.",
							   comment: "App settings control"),
			  keywords: [String(localized: "compact", comment: "Search keyword"),
						 String(localized: "layout", comment: "Search keyword")],
			  requiresConnection: false),
		.init(destination: .appSettings, screenTitle: screen,
			  sectionTitle: String(localized: "Environment", comment: "App settings section"),
			  listSection: .configure,
			  label: String(localized: "Weather Conditions", comment: "App settings control"),
			  requiresConnection: false),
		.init(destination: .appSettings, screenTitle: screen,
			  sectionTitle: String(localized: "App Data", comment: "App settings section"),
			  listSection: .configure,
			  label: String(localized: "Clear App Data", comment: "App settings control"),
			  subtitle: String(localized: "Delete every node, message and position stored on this device.",
							   comment: "App settings control"),
			  keywords: [String(localized: "erase", comment: "Search keyword"),
						 String(localized: "delete", comment: "Search keyword"),
						 String(localized: "reset", comment: "Search keyword")],
			  requiresConnection: false),
		.init(destination: .appSettings, screenTitle: screen,
			  sectionTitle: String(localized: "App Data", comment: "App settings section"),
			  listSection: .configure,
			  label: String(localized: "Reset App Settings", comment: "App settings control"),
			  requiresConnection: false),
		.init(destination: .appSettings, screenTitle: screen,
			  sectionTitle: String(localized: "Documentation Translations",
								   comment: "App settings section"),
			  listSection: .configure,
			  label: String(localized: "Participate in Distributed Translations",
							comment: "App settings control"),
			  keywords: [String(localized: "translate", comment: "Search keyword"),
						 String(localized: "language", comment: "Search keyword")],
			  requiresConnection: false)
	]

	// MARK: - Screens that are a destination in themselves

	private static let tools: [SettingsSearchEntry] = [
		.init(destination: .appSettings, screenTitle: screen, listSection: .configure,
			  label: String(localized: "App Settings", comment: "Settings screen"),
			  requiresConnection: false),
		.init(destination: .about, screenTitle: String(localized: "About", comment: "Settings screen"),
			  listSection: .configure,
			  label: String(localized: "About Meshtastic", comment: "Settings screen"),
			  keywords: [String(localized: "version", comment: "Search keyword"),
						 String(localized: "licence", comment: "Search keyword")],
			  requiresConnection: false),
		.init(destination: .helpDocs,
			  screenTitle: String(localized: "Help & Documentation", comment: "Settings screen"),
			  listSection: .configure,
			  label: String(localized: "Help & Documentation", comment: "Settings screen"),
			  keywords: [String(localized: "guide", comment: "Search keyword"),
						 String(localized: "manual", comment: "Search keyword")],
			  requiresConnection: false),
		.init(destination: .routes, screenTitle: String(localized: "Routes", comment: "Settings screen"),
			  listSection: .configure,
			  label: String(localized: "Routes", comment: "Settings screen"),
			  keywords: [String(localized: "track", comment: "Search keyword"),
						 String(localized: "gpx", comment: "Search keyword")],
			  requiresConnection: false)
	]

	// MARK: - Channels

	private static let channels: [SettingsSearchEntry] = [
		.init(destination: .channels,
			  screenTitle: String(localized: "Channels", comment: "Settings screen"),
			  listSection: .radioConfiguration,
			  label: String(localized: "Channels", comment: "Settings screen"),
			  subtitle: String(localized: "The channels this radio listens on, and their encryption keys.",
							   comment: "Settings screen"),
			  // "psk" is the spec's own worked example: nothing on screen says it, so
			  // without this the term finds nothing.
			  keywords: [String(localized: "psk", comment: "Search keyword"),
						 String(localized: "encryption", comment: "Search keyword"),
						 String(localized: "key", comment: "Search keyword"),
						 String(localized: "primary", comment: "Search keyword")]),
		.init(destination: .shareQRCode,
			  screenTitle: String(localized: "Share QR Code", comment: "Settings screen"),
			  listSection: .radioConfiguration,
			  label: String(localized: "Share QR Code", comment: "Settings screen"),
			  keywords: [String(localized: "qr", comment: "Search keyword"),
						 String(localized: "share", comment: "Search keyword"),
						 String(localized: "invite", comment: "Search keyword")])
	]

	private static let screen = String(localized: "App Settings", comment: "Settings screen")
	private static let sectionApp = String(localized: "App Settings", comment: "App settings section")
}
