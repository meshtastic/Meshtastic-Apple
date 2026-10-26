//
//  CinemaScene.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
import OSLog
import SwiftUI
#if os(visionOS)
import UIKit
#endif

/// A one-shot ask for the cinema's front screen to show something, from a tap on one of the
/// tent's boards; claimed by the cinema once it has it.
enum CinemaScreenRequest: Equatable {
	/// The Nodes section with this node's detail open.
	case node(Int64)
	/// The Map section with the coverage estimate form open for this node.
	case coverageEstimate(Int64)
}

/// The visionOS immersive space that shows the app on a big screen inside a 360° environment.
/// Only one immersive space can be open, so opening this one closes the showcase first.
enum CinemaScene {
	static let id = "cinema-space"

	#if os(visionOS)
	@MainActor private static var isOpening = false
	/// Set when the cinema closed the main window, so leaving it always brings the window back.
	@MainActor static var closedMainWindow = false
	/// Set while a main window the cinema asked for is still on its way, so the space's reopen on
	/// the way to the background, its onDisappear and the 3D map's backup don't open two. The next
	/// main window to appear clears it.
	@MainActor private(set) static var reopeningMainWindow = false

	/// Brings the main window back when none is open and none is on its way.
	@MainActor
	static func reopenMainWindow(_ openWindow: OpenWindowAction, appState: AppState) {
		guard appState.mainWindowCount == 0, !reopeningMainWindow else { return }
		reopeningMainWindow = true
		openWindow(id: MeshtasticAppleApp.mainWindowID)
	}

	/// A main window appeared, asked for or not.
	@MainActor
	static func mainWindowAppeared() {
		reopeningMainWindow = false
	}

	/// The app is back in the foreground and the main window it asked for on the way to the
	/// background never came: a backgrounded app may not get to open one. Asks again, unless a
	/// window is already there or on its way in (the app relaunched from Home opens one itself).
	@MainActor
	static func reopenMainWindowAfterBackground(_ openWindow: OpenWindowAction, appState: AppState) {
		guard reopeningMainWindow, !appState.cinemaOpen, !appState.showcaseOpen, !windowSceneExists else { return }
		reopeningMainWindow = false
		reopenMainWindow(openWindow, appState: appState)
	}

	/// Whether a window's scene is connected, showing or still on its way in. Scene configuration
	/// names are nil on visionOS, but the session role tells a window (the main window or the
	/// Mesh Map window) from the 3D map's volume and the immersive spaces.
	@MainActor private static var windowSceneExists: Bool {
		UIApplication.shared.connectedScenes.contains { $0.session.role == .windowApplication }
	}

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
