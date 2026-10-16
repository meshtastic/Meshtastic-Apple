//
//  SpatialTerrainKeeper.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//
import Foundation
import OSLog
import SwiftData

/// When the app checks the mesh's area for its offline map on its own: once soon after launch,
/// once after each new connection, then every few minutes while a radio is connected (the mesh
/// only changes while one is).
struct SpatialTerrainCheckSchedule: Equatable {
	static let interval: TimeInterval = 300

	private(set) var lastCheck: Date?
	private(set) var seenRadio: Int64?
	private(set) var connectedSinceCheck = false
	/// The state before the last check, so a check that couldn't read the mesh can be taken back.
	private var beforeCheck: Before?

	private struct Before: Equatable {
		let lastCheck: Date?
		let connectedSinceCheck: Bool
	}

	/// Called on every tick with the connected radio. True when the area should be checked now.
	/// `canCheck` is false while the setting is off, there is no managed region yet, the volume is
	/// open, or a download is running.
	mutating func shouldCheck(now: Date, radio: Int64?, canCheck: Bool) -> Bool {
		if radio != seenRadio {
			seenRadio = radio
			if radio != nil { connectedSinceCheck = true }
		}
		guard canCheck else { return false }
		let due: Bool
		if let lastCheck {
			due = connectedSinceCheck || (radio != nil && now.timeIntervalSince(lastCheck) >= Self.interval)
		} else {
			due = true
		}
		if due {
			beforeCheck = Before(lastCheck: lastCheck, connectedSinceCheck: connectedSinceCheck)
			lastCheck = now
			connectedSinceCheck = false
		}
		return due
	}

	/// Takes back the last check when it couldn't read the mesh, so the next tick tries again.
	mutating func undoLastCheck() {
		guard let beforeCheck else { return }
		lastCheck = beforeCheck.lastCheck
		connectedSinceCheck = connectedSinceCheck || beforeCheck.connectedSinceCheck
		self.beforeCheck = nil
	}
}

#if os(visionOS)
/// Keeps the app-managed offline map (streets and terrain) covering the mesh. It holds the one
/// automatic download and its retry rules, so the spatial map volume and the app's own check
/// never start two downloads or keep separate backoffs. The volume shows the progress and notes
/// from here.
@MainActor @Observable
final class SpatialTerrainKeeper {
	static let shared = SpatialTerrainKeeper()
	/// How often the app's own check wakes up. Most ticks only look at the schedule.
	static let tick: Duration = .seconds(30)
	/// Same keys as the spatial map's settings.
	static let autoTerrainKey = "spatialMapAutoTerrain"
	static let preciseOnlyKey = "enableMapPreciseLocationsOnly"

	private(set) var backoff = SpatialTerrainBackoff()
	private(set) var isDownloading = false
	/// Caption for a failed automatic download, shown in the volume with a retry button.
	private(set) var note: String?
	/// The last area whose street map was over the per-map limit, so only terrain was kept there.
	/// Inside it terrain alone counts as covered, for the rest of the session.
	private(set) var streetsTooLarge: GeoBounds?

	@ObservationIgnored private var automatic = false
	@ObservationIgnored private var cancelled = false
	/// The manager took the download (it didn't refuse it up front).
	@ObservationIgnored private var began = false
	@ObservationIgnored private var target: GeoBounds?
	@ObservationIgnored private var onFailure: ((String) -> Void)?
	@ObservationIgnored private var schedule = SpatialTerrainCheckSchedule()
	@ObservationIgnored private var openVolumes = 0
	@ObservationIgnored private var loop: Task<Void, Never>?

	private init() {}

	/// Whether automatic downloads have stopped for this area (cancelled or failed too often).
	func gaveUp(on target: GeoBounds) -> Bool {
		backoff.gaveUp(on: target)
	}

	/// True once a failed automatic download's wait is over. Clears the wait, so it reads true once.
	func takeRetryDue(now: Date = Date()) -> Bool {
		guard let target = backoff.target, !backoff.gaveUp(on: target),
			  let retryAfter = backoff.retryAfter, now >= retryAfter else { return false }
		backoff.retryAfter = nil
		return true
	}

	/// Downloads the offline map (streets and terrain) so it covers `box`: a new app-managed
	/// region, or a bigger one that replaces it. A manual start ignores the retry rules and reports
	/// a failure to `onFailure`; an automatic one leaves it in `note`. With `growOnly` it never
	/// creates the region, only grows it. False when nothing was started.
	@discardableResult
	func start(box: GeoBounds, automatic: Bool, growOnly: Bool = false, onFailure: ((String) -> Void)? = nil) -> Bool {
		guard !isDownloading else { return false }
		let manager = OfflineMapManager.shared
		manager.loadIfNeeded()
		if !automatic { backoff = SpatialTerrainBackoff() }
		let decision = SpatialTerrainAutoDecision.make(
			box: box, regions: manager.regions,
			isBusy: manager.isBusy, backoff: backoff, now: Date(), growOnly: growOnly,
			streetsTooLarge: streetsTooLarge
		)
		guard let target = decision.target else {
			Logger.services.debug("🧊 [Spatial] Terrain check: \(String(describing: decision), privacy: .public)")
			return false
		}
		isDownloading = true
		cancelled = false
		began = false
		self.automatic = automatic
		self.target = target
		self.onFailure = onFailure
		note = nil
		let estimate = ByteCountFormatter.string(fromByteCount: SpatialTerrainAutoDecision.estimatedBytes(target), countStyle: .file)
		Logger.services.info("🧊 [Spatial] Map download (\(automatic ? "automatic" : "manual", privacy: .public)): \(String(describing: decision), privacy: .public), about \(estimate, privacy: .public)")
		manager.downloadManagedMap(
			bounds: target,
			smallerAreas: SpatialTerrainAutoDecision.smallerAreas(than: target, box: box),
			includeRegional: SpatialTerrainAutoDecision.includesRegional(target)
		) { [weak self] result in
			self?.finish(result: result)
		}
		// Set after the call: a refusal up front completes synchronously, before this line.
		if isDownloading, manager.activeDownload != nil { began = true }
		return true
	}

	func cancel() {
		guard isDownloading else { return }
		cancelled = true
		OfflineMapManager.shared.cancelDownload()
	}

	private func finish(result: OfflineManagedMapResult) {
		guard isDownloading else { return }
		isDownloading = false
		Logger.services.info("🧊 [Spatial] Map download \(result == .failed ? (self.cancelled ? "cancelled" : "failed") : String(describing: result), privacy: .public)")
		let target = target
		let onFailure = onFailure
		self.target = nil
		self.onFailure = nil
		if result != .failed {
			backoff = SpatialTerrainBackoff()
			// Without this the next check would try the same street map again.
			if result == .streetsTooLarge { streetsTooLarge = target }
			return
		}
		let manager = OfflineMapManager.shared
		let failed: String? = if case .failed(let message) = manager.activeDownload?.state { message } else { nil }
		// A download that started and ended without failing was cancelled, in the volume or in Offline Maps.
		if cancelled || (began && failed == nil) {
			if let target { backoff.recordCancel(target) }
			return
		}
		if let target { backoff.recordFailure(target, now: Date()) }
		if failed != nil { manager.dismissDownload() }
		let message = failed ?? String(localized: "The terrain download could not start.", comment: "Spatial map: alert message when the manager refuses the terrain download")
		if automatic || onFailure == nil {
			note = message
		} else {
			onFailure?(message)
		}
	}

	// MARK: - App-level check

	/// While the volume is open it keeps its own box covered, so the app's check stands aside.
	func volumeAppeared() { openVolumes += 1 }
	func volumeDisappeared() { openVolumes = max(0, openVolumes - 1) }

	/// Runs the app's own check while the app is active and stops it otherwise. `container` is
	/// read on each check and returns nil while the database is being reset.
	func setAppActive(_ active: Bool, container: @escaping @MainActor () -> ModelContainer?) {
		loop?.cancel()
		loop = nil
		guard active else { return }
		loop = Task {
			while !Task.isCancelled {
				guard (try? await Task.sleep(for: Self.tick)) != nil else { return }
				await checkIfDue(container: container)
			}
		}
	}

	/// Reads the mesh's nodes off the main thread when the schedule says so, and grows the managed
	/// offline map when it doesn't cover the circle the volume would show for them. Only the spatial
	/// map creates the region, so nothing downloads for someone who never opened it or deleted it.
	private func checkIfDue(container: @MainActor () -> ModelContainer?) async {
		let defaults = UserDefaults.standard
		let enabled = defaults.object(forKey: Self.autoTerrainKey) as? Bool ?? true
		let radio = AccessoryManager.shared.activeDeviceNum
		let manager = OfflineMapManager.shared
		manager.loadIfNeeded()
		let hasRegion = manager.regions.contains(where: \.isAppManaged)
		let canCheck = enabled && hasRegion && openVolumes == 0 && !isDownloading && !manager.isBusy
		// The container first: while the database resets, the scheduled check waits instead of being used up.
		guard let container = container(), schedule.shouldCheck(now: Date(), radio: radio, canCheck: canCheck) else { return }
		let preciseOnly = defaults.bool(forKey: Self.preciseOnlyKey)
		let nodes: [SpatialNodeSnapshot]
		do {
			nodes = try await SpatialMeshAreaReader.nodes(container: container, preciseOnly: preciseOnly, connectedNodeNum: radio)
		} catch {
			// A failed read isn't an empty mesh: try again on the next tick.
			Logger.services.error("🧊 [Spatial] App terrain check could not read the nodes: \(error.localizedDescription, privacy: .public)")
			schedule.undoLastCheck()
			return
		}
		// The app may have left the foreground, or the volume opened, while the read ran.
		guard !Task.isCancelled, openVolumes == 0, let box = SpatialMapArea.meshCircle(nodes)?.bounds else { return }
		Logger.services.debug("🧊 [Spatial] App terrain check: \(nodes.count, privacy: .public) nodes")
		start(box: box, automatic: true, growOnly: true)
	}
}

/// Reads the spatial map's node list on a background context for the app's terrain check. Create
/// it off the main thread: a model actor created on the main thread runs its work there.
@ModelActor
actor SpatialMeshAreaReader {
	func nodes(preciseOnly: Bool, connectedNodeNum: Int64?) throws -> [SpatialNodeSnapshot] {
		try SpatialMapNodeSource.snapshots(context: modelContext, preciseOnly: preciseOnly, connectedNodeNum: connectedNodeNum)
	}

	nonisolated static func nodes(container: ModelContainer, preciseOnly: Bool, connectedNodeNum: Int64?) async throws -> [SpatialNodeSnapshot] {
		try await Task.detached(priority: .utility) {
			try await SpatialMeshAreaReader(modelContainer: container).nodes(preciseOnly: preciseOnly, connectedNodeNum: connectedNodeNum)
		}.value
	}
}
#endif
