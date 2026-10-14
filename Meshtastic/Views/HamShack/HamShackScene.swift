//
//  HamShackScene.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import OSLog
import SwiftUI

/// The visionOS immersive space that shows the mesh as radios in a ham shack. There is only ever
/// one; `open` refuses while it is showing or already opening.
enum HamShackScene {
	static let id = "hamshack-space"

	#if os(visionOS)
	@MainActor private static var isOpening = false

	/// Opens the space unless it is open or opening. Returns whether it is open afterwards.
	@MainActor @discardableResult
	static func open(_ openImmersiveSpace: OpenImmersiveSpaceAction, appState: AppState) async -> Bool {
		guard !appState.hamShackOpen, !isOpening else { return appState.hamShackOpen }
		isOpening = true
		defer { isOpening = false }
		switch await openImmersiveSpace(id: id) {
		case .opened:
			appState.hamShackOpen = true
			return true
		case .userCancelled:
			Logger.services.info("📻 [Shack] Opening the shack was cancelled")
		case .error:
			Logger.services.error("📻 [Shack] The shack could not be opened")
		@unknown default:
			Logger.services.error("📻 [Shack] Unknown result opening the shack")
		}
		return false
	}
	#endif
}
