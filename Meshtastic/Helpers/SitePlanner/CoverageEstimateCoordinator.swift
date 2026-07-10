//
//  CoverageEstimateCoordinator.swift
//  Meshtastic
//
//  App-wide owner of the current Site Planner coverage estimate, if any. Enforces
//  "only one in-flight run at a time" (FR-007) at the source rather than merely
//  disabling a button, and routes a successful bridge result into MapDataManager's
//  existing import pipeline. See specs/015-site-planner-outbound/data-model.md
//  ("CoverageEstimateState").
//

import Foundation
import OSLog

/// The lifecycle of one coverage estimate — see data-model.md.
enum CoverageEstimateState: Equatable {
	case idle
	case running(startedAt: Date)
	case succeeded(overlay: MapDataMetadata)
	case failed(reason: CoverageEstimateRunError)
	case canceled

	static func == (lhs: CoverageEstimateState, rhs: CoverageEstimateState) -> Bool {
		switch (lhs, rhs) {
		case (.idle, .idle), (.canceled, .canceled):
			return true
		case (.running(let lStarted), .running(let rStarted)):
			return lStarted == rStarted
		case (.succeeded(let lOverlay), .succeeded(let rOverlay)):
			return lOverlay.id == rOverlay.id
		case (.failed(let lReason), .failed(let rReason)):
			return lReason == rReason
		default:
			return false
		}
	}
}

enum CoverageEstimateRunError: LocalizedError, Equatable {
	case alreadyRunning
	case bridge(CoverageEstimateBridge.BridgeError)
	case importFailed(String)

	var errorDescription: String? {
		switch self {
		case .alreadyRunning:
			return "A coverage estimate is already running.".localized
		case .bridge(let bridgeError):
			return bridgeError.errorDescription
		case .importFailed(let message):
			return message
		}
	}

	static func == (lhs: CoverageEstimateRunError, rhs: CoverageEstimateRunError) -> Bool {
		lhs.errorDescription == rhs.errorDescription
	}
}

@MainActor
final class CoverageEstimateCoordinator: ObservableObject {

	static let shared = CoverageEstimateCoordinator()

	@Published private(set) var state: CoverageEstimateState = .idle

	private var bridge: CoverageEstimateBridge?
	private var runTask: Task<Void, Never>?

	/// Identifies the current run so a superseded run's eventual completion (it was
	/// canceled, but its `Task` hasn't unwound yet) can't clobber a state transition
	/// that happened after it — `reset()`/a fresh `start()` mint a new token, and
	/// `finish()` only applies if its captured token still matches.
	private var currentRunToken: UUID?

	private init() {}

	/// Starts a coverage estimate for `params`, enforcing the one-in-flight rule
	/// (FR-007). Returns immediately once state transitions to `.running`; observe
	/// `state` for the eventual `.succeeded`/`.failed`/`.canceled` outcome.
	func start(_ params: CoverageEstimateParameters) {
		guard case .idle = state else {
			let currentState = state
			Logger.services.warning("🛰️ [SitePlanner] Ignored start() while a coverage estimate is already \(String(describing: currentState), privacy: .public)")
			return
		}
		guard params.isValid else {
			state = .failed(reason: .importFailed(params.validationErrors().first?.localizedDescription ?? "Invalid parameters."))
			return
		}

		let token = UUID()
		currentRunToken = token
		state = .running(startedAt: Date())
		Logger.services.info("🛰️ [SitePlanner] Coverage estimate started")

		let bridge = CoverageEstimateBridge()
		self.bridge = bridge

		runTask = Task { [weak self] in
			do {
				let data = try await bridge.run(params)
				try Task.checkCancellation()
				let overlay = try await MapDataManager.shared.importFromData(data, suggestedName: params.name)
				self?.finish(.succeeded(overlay: overlay), token: token)
			} catch is CancellationError {
				self?.finish(.canceled, token: token)
			} catch let bridgeError as CoverageEstimateBridge.BridgeError {
				Logger.services.error("🛰️ [SitePlanner] Coverage estimate failed: \(bridgeError.localizedDescription, privacy: .public)")
				self?.finish(.failed(reason: .bridge(bridgeError)), token: token)
			} catch {
				Logger.services.error("🛰️ [SitePlanner] Coverage estimate import failed: \(error.localizedDescription, privacy: .public)")
				self?.finish(.failed(reason: .importFailed(error.localizedDescription)), token: token)
			}
		}
	}

	/// Cancels the in-flight estimate, if any (FR-008). No-op when idle. The eventual
	/// `.canceled` state transition happens asynchronously, once the running `Task`
	/// unwinds — call `reset()` instead if a synchronous return to `.idle` is needed.
	func cancel() {
		guard case .running = state else { return }
		Logger.services.info("🛰️ [SitePlanner] Coverage estimate canceled by user")
		runTask?.cancel()
		bridge?.cancel()
	}

	/// Returns to `.idle` after inspecting a terminal state (`.succeeded`/`.failed`/
	/// `.canceled`), so the UI can start a fresh estimate. No-op while `.running`.
	func acknowledge() {
		guard case .running = state else {
			state = .idle
			return
		}
	}

	/// Synchronously forces `.idle` regardless of current state, canceling any
	/// in-flight run and invalidating its token so a late completion can't overwrite
	/// whatever runs next. Primarily for test isolation between cases sharing `.shared`.
	func reset() {
		runTask?.cancel()
		bridge?.cancel()
		currentRunToken = nil
		bridge = nil
		runTask = nil
		state = .idle
	}

	private func finish(_ result: CoverageEstimateState, token: UUID) {
		guard currentRunToken == token else {
			return // superseded by a reset()/newer start() — don't clobber current state
		}
		bridge = nil
		runTask = nil
		currentRunToken = nil
		state = result
		switch result {
		case .succeeded:
			Logger.services.info("🛰️ [SitePlanner] Coverage estimate succeeded")
		case .failed(let reason):
			Logger.services.error("🛰️ [SitePlanner] Coverage estimate ended in failure: \(reason.localizedDescription ?? "unknown", privacy: .public)")
		case .canceled:
			Logger.services.info("🛰️ [SitePlanner] Coverage estimate ended: canceled")
		default:
			break
		}
	}
}
