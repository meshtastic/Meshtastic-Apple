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

	var id: String { rawValue }

	var title: String {
		switch self {
		case .sarTent:
			String(localized: "Search and Rescue Tent", comment: "Cinema environment: inside a search and rescue command tent")
		case .hamShack:
			String(localized: "Ham Shack", comment: "Cinema environment: inside an amateur radio operator's radio room")
		}
	}

	/// The environment's image in CinemaContent.
	var imageName: String {
		switch self {
		case .sarTent: "sar_tent"
		case .hamShack: "ham_shack"
		}
	}

	/// What the board of the nodes' status messages is called in this place. The tent's is a status
	/// board; the ham shack's is where net control logs the check-ins.
	var statusBoardTitle: String {
		switch self {
		case .sarTent:
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
		}
	}

	/// What the status board says while no node has a status message.
	var statusBoardEmptyTitle: String {
		switch self {
		case .sarTent:
			String(localized: "No status yet", comment: "Cinema: shown on the tent's status board while no node has a status message")
		case .hamShack:
			String(localized: "No check-ins yet", comment: "Cinema: shown on the ham shack's check-in board while no node has a status message")
		}
	}

	/// Turns the backdrop and its boards together about the viewer, radians to the left, so the
	/// part of the image left quiet for the window is in front. The images are rendered with that
	/// part at their center, which the backdrop already puts in front, so this is zero unless an
	/// image needs nudging.
	var frontRotation: Float {
		switch self {
		case .sarTent, .hamShack: 0
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
		}
	}
}
#endif
