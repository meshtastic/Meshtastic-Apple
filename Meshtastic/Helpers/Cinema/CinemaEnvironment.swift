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
		case .sarTent, .fireLookout, .castleTower:
			String(localized: "Status Board", comment: "Cinema: title of the board of the nodes' status messages in the tent")
		case .hamShack:
			String(localized: "Net Check-In", comment: "Cinema: title of the ham shack's status board, where net control logs the check-ins")
		}
	}

	/// Whether the status board stands portrait, as the tent's does beside the screen, rather than
	/// lying down like the team roster's whiteboard.
	var statusBoardPortrait: Bool {
		switch self {
		case .sarTent, .hamShack: true
		case .fireLookout, .castleTower: false
		}
	}

	/// What the status board says while no node has a status message.
	var statusBoardEmptyTitle: String {
		switch self {
		case .sarTent, .fireLookout, .castleTower:
			String(localized: "No status yet", comment: "Cinema: shown on the tent's status board while no node has a status message")
		case .hamShack:
			String(localized: "No check-ins yet", comment: "Cinema: shown on the ham shack's check-in board while no node has a status message")
		}
	}

	/// Whether the image is a cutout: transparent wherever the camera saw past the room's glass, so
	/// a sky, and real terrain when the app has some, are drawn behind it.
	var isCutout: Bool {
		standsOnSummit
	}

	/// Whether it stands on a summit found in the downloaded terrain, with the real terrain and the
	/// nodes out round it, and on the 3D map.
	var standsOnSummit: Bool {
		self == .fireLookout || self == .castleTower
	}

	/// Whether the boards are scrolls that roll up out of the view.
	var hasScrolls: Bool {
		self == .castleTower
	}

	/// The sky painted behind a cutout: the one the room was lit by, with its own horizon. The
	/// castle is lit as the lookout is, so it shares the lookout's skies.
	var skyImageName: String? {
		switch self {
		case .fireLookout, .castleTower: "fire_lookout_sky"
		default: nil
		}
	}

	/// The same sky with nothing below the horizon, for behind real terrain.
	var clearSkyImageName: String? {
		switch self {
		case .fireLookout, .castleTower: "fire_lookout_puresky"
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
		case .sarTent, .hamShack, .fireLookout, .castleTower: 0
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
