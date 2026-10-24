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

	var id: String { rawValue }

	var title: String {
		switch self {
		case .sarTent:
			String(localized: "Search and Rescue Tent", comment: "Cinema environment: inside a search and rescue command tent")
		}
	}

	/// The environment's image in CinemaContent.
	var imageName: String {
		switch self {
		case .sarTent: "sar_tent"
		}
	}

	/// Turns the sphere so the part of the image left quiet for the window is in front. The
	/// images are rendered with that part at their center, which a RealityKit sphere puts a
	/// quarter turn to the right.
	var frontRotation: Float {
		switch self {
		case .sarTent: .pi / 2
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
		}
	}
}
#endif
