//
//  OpenMeshScreenIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//
//  Opens the app on a screen, for the Control Center controls. Compiled into
//  both the app and the widget extension: the control runs it from the
//  extension, and because it opens the app when run, the system performs it
//  in the app, which routes to the screen like a notification tap does.
//  OpenURLIntent would be simpler, but it's only supported for universal
//  links, not the app's meshtastic:// scheme.
//

import AppIntents
import Foundation

/// A screen a control can open.
enum MeshScreen: String, AppEnum {
	case messages
	case connect
	case map

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Screen")
	static let caseDisplayRepresentations: [MeshScreen: DisplayRepresentation] = [
		.messages: "Messages",
		.connect: "Connect",
		.map: "Node Map"
	]

	/// The app's deep link for the screen.
	var url: URL {
		switch self {
		case .messages: URL(string: "meshtastic:///messages")!
		case .connect: URL(string: "meshtastic:///connect")!
		case .map: URL(string: "meshtastic:///map")!
		}
	}
}

struct OpenMeshScreenIntent: AppIntent {
	static let title: LocalizedStringResource = "Open Meshtastic Screen"
	static let description = IntentDescription("Opens Meshtastic on a screen.")
	static let openAppWhenRun = true
	/// Only for the controls; Shortcuts users have the app's own actions.
	static let isDiscoverable = false

	@Parameter(title: "Screen")
	var screen: MeshScreen

	init() {}

	init(screen: MeshScreen) {
		self.screen = screen
	}

	@MainActor
	func perform() async throws -> some IntentResult {
		MeshScreenOpener.open(screen.url)
		return .result()
	}
}

/// Hands a screen's deep link to the app. The app sets `handler` at launch;
/// a link that arrives before that is held and delivered when it's set.
@MainActor
enum MeshScreenOpener {
	static var handler: ((URL) -> Void)? {
		didSet {
			if let handler, let pending {
				self.pending = nil
				handler(pending)
			}
		}
	}

	private static var pending: URL?

	static func open(_ url: URL) {
		if let handler {
			handler(url)
		} else {
			pending = url
		}
	}
}
