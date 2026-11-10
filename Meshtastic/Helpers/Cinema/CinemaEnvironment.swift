//
//  CinemaEnvironment.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import SwiftUI

/// A place the cinema can be set in. Each is a 360° equirectangular image wrapped around the
/// viewer, with the screen in front of the part of the image left quiet for it.
enum CinemaEnvironment: String, CaseIterable, Identifiable {
	case sarTent
	case hamShack
	case fireLookout
	case castleTower
	case cityRooftop
	case spaceStation

	var id: String { rawValue }

	var title: String {
		switch self {
		case .sarTent:
			String(localized: "Search and Rescue Tent", comment: "Cinema environment: inside a search and rescue command tent")
		case .hamShack:
			String(localized: "Ham Shack", comment: "Cinema environment: inside an amateur radio operator's radio room")
		case .fireLookout:
			String(localized: "Fire Lookout", comment: "Cinema environment: inside a fire lookout cab on a mountain summit")
		case .castleTower:
			String(localized: "Castle Tower", comment: "Cinema environment: on the open top of a medieval castle tower on a mountain summit")
		case .cityRooftop:
			String(localized: "City Rooftop", comment: "Cinema environment: on the roof deck of a tall downtown building at dusk")
		case .spaceStation:
			String(localized: "Space Station", comment: "Cinema environment: inside a space station module under its cupola, with Earth through the windows")
		}
	}

	/// The environment's name in CinemaContent: its anchors file, and its image unless it comes in
	/// more than one stone.
	var imageName: String {
		switch self {
		case .sarTent: "sar_tent"
		case .hamShack: "ham_shack"
		case .fireLookout: "fire_lookout"
		case .castleTower: "castle_tower"
		case .cityRooftop: "city_rooftop"
		case .spaceStation: "space_cupola"
		}
	}

	/// The environment's image in CinemaContent, in `stone` where it's built of stone.
	func imageName(stone: CastleStone) -> String {
		self == .castleTower ? "\(imageName)_\(stone.rawValue)" : imageName
	}

	/// Whether the stone it's built of can be chosen.
	var hasStone: Bool {
		self == .castleTower
	}

	/// What the board of the nodes' status messages is called in this place. The tent's is a status
	/// board; the ham shack's is where net control logs the check-ins.
	var statusBoardTitle: String {
		switch self {
		case .sarTent, .fireLookout, .castleTower, .cityRooftop, .spaceStation:
			String(localized: "Status Board", comment: "Cinema: title of the board of the nodes' status messages in the tent")
		case .hamShack:
			String(localized: "Net Check-In", comment: "Cinema: title of the ham shack's status board, where net control logs the check-ins")
		}
	}

	/// Whether the status board stands portrait, as the tent's does beside the screen, rather than
	/// lying down like the team roster's whiteboard.
	var statusBoardPortrait: Bool {
		switch self {
		case .sarTent, .hamShack, .cityRooftop: true
		case .fireLookout, .castleTower, .spaceStation: false
		}
	}

	/// What the status board says while no node has a status message.
	var statusBoardEmptyTitle: String {
		switch self {
		case .sarTent, .fireLookout, .castleTower, .cityRooftop, .spaceStation:
			String(localized: "No status yet", comment: "Cinema: shown on the tent's status board while no node has a status message")
		case .hamShack:
			String(localized: "No check-ins yet", comment: "Cinema: shown on the ham shack's check-in board while no node has a status message")
		}
	}

	/// Whether the image is a cutout: transparent wherever the camera saw past the room's glass, so
	/// a sky, and real terrain when the app has some, are drawn behind it. The space station has no
	/// terrain, only Earth painted behind its windows.
	var isCutout: Bool {
		siteKind != nil || self == .spaceStation
	}

	/// What it stands on in the downloaded maps, with the real terrain and the nodes out round it:
	/// a summit, or the roof of one of the tallest buildings. Nil for a room with no view of its own.
	var siteKind: LookoutSiteKind? {
		switch self {
		case .fireLookout, .castleTower: .summit
		case .cityRooftop: .rooftop
		case .sarTent, .hamShack: nil
		}
	}

	/// Whether it stands on a summit found in the downloaded terrain, and on the 3D map there.
	var standsOnSummit: Bool {
		siteKind == .summit
	}

	/// The title over the panel's dial that turns the room on its site.
	var turnDialTitle: String {
		switch self {
		case .cityRooftop:
			String(localized: "Turn Rooftop", comment: "Cinema: title over the dial that turns the city rooftop, so the screen looks out over another part of the view")
		default:
			String(localized: "Turn Lookout", comment: "Cinema: title over the dial that turns the fire lookout, so the screen looks out over another part of the view")
		}
	}

	/// Whether the boards are scrolls that roll up out of the view.
	var hasScrolls: Bool {
		self == .castleTower
	}

	/// The sky painted behind a cutout: the one the room was lit by, with its own horizon. The
	/// castle is lit as the lookout is, so it shares the lookout's skies. The rooftop is lit by the
	/// lookout's clear sky, with a made-up city under it.
	var skyImageName: String? {
		switch self {
		case .fireLookout, .castleTower: "fire_lookout_sky"
		case .cityRooftop: "city_rooftop_sky"
		case .spaceStation: "space_earth"
		default: nil
		}
	}

	/// The same sky with nothing below the horizon, for behind real terrain. Only the environments
	/// that stand on a summit have one.
	var clearSkyImageName: String? {
		switch self {
		case .fireLookout, .castleTower, .cityRooftop: "fire_lookout_puresky"
		default: nil
		}
	}

	/// Where the sun is in a cutout's sky, so terrain can be shaded to match: degrees clockwise
	/// from the image's center, and above the horizon.
	var sun: (azimuth: Float, elevation: Float) {
		(134, 5)
	}

	/// Turns the backdrop and its boards together about the viewer, radians to the left, so the
	/// part of the image left quiet for the window is in front. The images are rendered with that
	/// part at their center, which the backdrop already puts in front, so this is zero unless an
	/// image needs nudging.
	var frontRotation: Float {
		switch self {
		case .sarTent, .hamShack, .fireLookout, .castleTower, .cityRooftop, .spaceStation: 0
		}
	}

	/// Colors for the backdrop shown if the environment's image can't be loaded: sky at the top,
	/// the horizon, and the ground.
	var placeholderColors: (sky: UIColor, horizon: UIColor, ground: UIColor) {
		switch self {
		case .sarTent:
			(
				UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1),
				UIColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1),
				UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1)
			)
		case .hamShack:
			(
				UIColor(red: 0.85, green: 0.84, blue: 0.80, alpha: 1),
				UIColor(red: 0.55, green: 0.36, blue: 0.18, alpha: 1),
				UIColor(red: 0.05, green: 0.08, blue: 0.07, alpha: 1)
			)
		case .fireLookout:
			(
				UIColor(red: 0.35, green: 0.45, blue: 0.70, alpha: 1),
				UIColor(red: 0.90, green: 0.60, blue: 0.30, alpha: 1),
				UIColor(red: 0.30, green: 0.22, blue: 0.15, alpha: 1)
			)
		case .castleTower:
			(
				UIColor(red: 0.45, green: 0.58, blue: 0.75, alpha: 1),
				UIColor(red: 0.85, green: 0.70, blue: 0.50, alpha: 1),
				UIColor(red: 0.30, green: 0.29, blue: 0.28, alpha: 1)
			)
		case .cityRooftop:
			(
				UIColor(red: 0.42, green: 0.55, blue: 0.75, alpha: 1),
				UIColor(red: 0.82, green: 0.68, blue: 0.52, alpha: 1),
				UIColor(red: 0.36, green: 0.27, blue: 0.19, alpha: 1)
			)
		case .spaceStation:
			(
				UIColor(red: 0.12, green: 0.25, blue: 0.50, alpha: 1),
				UIColor(red: 0.72, green: 0.72, blue: 0.70, alpha: 1),
				UIColor(red: 0.32, green: 0.32, blue: 0.31, alpha: 1)
			)
		}
	}
}

/// The stone the castle tower is built of.
enum CastleStone: String, CaseIterable, Identifiable {
	case gray
	case pink

	/// Where the cinema keeps the stone chosen.
	static let key = "cinemaCastleStone"

	var id: String { rawValue }

	var title: String {
		switch self {
		case .gray:
			String(localized: "Gray", comment: "Cinema: the castle tower built of gray stone")
		case .pink:
			String(localized: "Pink", comment: "Cinema: the castle tower built of pink stone")
		}
	}
}
#endif
