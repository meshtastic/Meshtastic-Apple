//
//  ShowcaseScene.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import OSLog
import SwiftUI

/// The visionOS immersive space that shows the mesh as radios in a showcase. There is only ever
/// one; `open` refuses while it is showing or already opening, and closes the cinema first.
enum ShowcaseScene {
	static let id = "hamshowcase-space"

	#if os(visionOS)
	@MainActor private static var isOpening = false

	/// Opens the space unless it is open or opening. Returns whether it is open afterwards.
	@MainActor @discardableResult
	static func open(_ openImmersiveSpace: OpenImmersiveSpaceAction, dismissImmersiveSpace: DismissImmersiveSpaceAction, appState: AppState) async -> Bool {
		guard !appState.showcaseOpen, !isOpening else { return appState.showcaseOpen }
		isOpening = true
		defer { isOpening = false }
		if appState.cinemaOpen {
			await dismissImmersiveSpace()
		}
		switch await openImmersiveSpace(id: id) {
		case .opened:
			appState.showcaseOpen = true
			return true
		case .userCancelled:
			Logger.services.info("📻 [Showcase] Opening the showcase was cancelled")
		case .error:
			Logger.services.error("📻 [Showcase] The showcase could not be opened")
		@unknown default:
			Logger.services.error("📻 [Showcase] Unknown result opening the showcase")
		}
		return false
	}
	#endif
}
