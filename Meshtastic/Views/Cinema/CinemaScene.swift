//
//  CinemaScene.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
import OSLog
import SwiftUI

/// The visionOS immersive space that shows the app on a big screen inside a 360° environment.
/// Only one immersive space can be open, so opening this one closes the showcase first.
enum CinemaScene {
	static let id = "cinema-space"

	#if os(visionOS)
	@MainActor private static var isOpening = false

	/// Opens the space unless it is open or opening. Returns whether it is open afterwards.
	@MainActor @discardableResult
	static func open(_ openImmersiveSpace: OpenImmersiveSpaceAction, dismissImmersiveSpace: DismissImmersiveSpaceAction, appState: AppState) async -> Bool {
		guard !appState.cinemaOpen, !isOpening else { return appState.cinemaOpen }
		isOpening = true
		defer { isOpening = false }
		if appState.showcaseOpen {
			await dismissImmersiveSpace()
		}
		switch await openImmersiveSpace(id: id) {
		case .opened:
			appState.cinemaOpen = true
			return true
		case .userCancelled:
			Logger.services.info("🎬 [Cinema] Opening the cinema was cancelled")
		case .error:
			Logger.services.error("🎬 [Cinema] The cinema could not be opened")
		@unknown default:
			Logger.services.error("🎬 [Cinema] Unknown result opening the cinema")
		}
		return false
	}
	#endif
}
