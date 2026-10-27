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
	/// The Map section with this trace route drawn and framed.
	case traceRoute(Int64)
}

/// A device model to stand in front of the viewer in the cinema, from the "View in your space"
/// button on a 3D model.
struct CinemaModelRequest: Equatable {
	/// The model file's name, without the .usdz.
	let modelName: String
	let deviceName: String
	/// The node it's a model of, for the live readings beside it. Nil for Chirpy.
	let nodeNum: Int64?
}

/// The visionOS immersive space that shows the app on a big screen inside a 360° environment.
/// Only one immersive space can be open, so opening this one closes the showcase first.
enum CinemaScene {
	static let id = "cinema-space"

	/// Keeps the paths that bring the main window back from opening two: set when a window is
	/// asked for, clear once one appears. A request made while the app is inactive can be
	/// dropped, so after a while without a window it is given up on and the next ask goes through.
	struct ReopenLatch {
		/// How long a request is trusted to bring a window.
		static let timeout: TimeInterval = 3
		private(set) var requestedAt: Date?

		/// Whether a window was asked for and none has appeared since, dropped or not.
		var awaitingWindow: Bool { requestedAt != nil }

		/// Whether a request is still on its way.
		func isPending(at now: Date) -> Bool {
			timeRemaining(at: now) > 0
		}

		/// How much longer the request on its way is trusted for; zero without one.
		func timeRemaining(at now: Date) -> TimeInterval {
			guard let requestedAt else { return 0 }
			return max(0, Self.timeout - now.timeIntervalSince(requestedAt))
		}

		/// Records an ask for a window unless one is on its way. Returns whether to open one.
		mutating func request(at now: Date) -> Bool {
			guard !isPending(at: now) else { return false }
			requestedAt = now
			return true
		}

		/// A main window appeared, asked for or not.
		mutating func windowAppeared() {
			requestedAt = nil
		}
	}

	#if os(visionOS)
	@MainActor private static var isOpening = false
	/// Set when the cinema closed the main window, so leaving it always brings the window back.
	@MainActor static var closedMainWindow = false
	/// Set while the cinema is open: stands a device model in front of the viewer. A Quick Look
	/// window would take them out of the tent to show it.
	@MainActor static var showModel: ((CinemaModelRequest) -> Void)?
	@MainActor private static var latch = ReopenLatch()
	/// Asks again once a request on its way has had its time, in case it was dropped.
	@MainActor private static var retry: Task<Void, Never>?

	/// Brings the main window back when none is open. Scene configuration names are nil on
	/// visionOS and the session role can't tell the main window from the Mesh Map window, so the
	/// count the main windows keep is the only check. While a window asked for is still on its
	/// way, waits for it and asks again if it never comes.
	@MainActor
	static func reopenMainWindow(_ openWindow: OpenWindowAction, appState: AppState) {
		guard appState.mainWindowCount == 0 else { return }
		let now = Date()
		if latch.request(at: now) {
			openWindow(id: MeshtasticAppleApp.mainWindowID)
		} else {
			retryLater(after: latch.timeRemaining(at: now), openWindow, appState: appState)
		}
	}

	/// A main window appeared, asked for or not.
	@MainActor
	static func mainWindowAppeared() {
		latch.windowAppeared()
		retry?.cancel()
		retry = nil
	}

	/// The app is back in the foreground and a main window the cinema asked for never came: a
	/// request made on the way to the background can be dropped. Asks again, after a window the
	/// system opens itself (the app relaunched from Home) has had a moment to appear, and not
	/// into an open space, whose way out brings the window back.
	@MainActor
	static func reopenMainWindowAfterBackground(_ openWindow: OpenWindowAction, appState: AppState) {
		guard latch.awaitingWindow else { return }
		retry?.cancel()
		retry = Task {
			try? await Task.sleep(for: .seconds(1))
			guard !Task.isCancelled, !appState.cinemaOpen, !appState.showcaseOpen else { return }
			reopenMainWindow(openWindow, appState: appState)
		}
	}

	/// Asks for the main window again after a delay. Not from the background, where the ask may
	/// be dropped again; the return to the foreground asks instead.
	@MainActor
	private static func retryLater(after delay: TimeInterval, _ openWindow: OpenWindowAction, appState: AppState) {
		retry?.cancel()
		retry = Task {
			try? await Task.sleep(for: .seconds(delay))
			guard !Task.isCancelled, UIApplication.shared.applicationState != .background else { return }
			reopenMainWindow(openWindow, appState: appState)
		}
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
