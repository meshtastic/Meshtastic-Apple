//
//  WatchSessionManager.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import WatchConnectivity
@preconcurrency import SwiftData
import CoreLocation
import os

/// Manages the WatchConnectivity session on the iOS side, sending mesh node
/// data to the companion Apple Watch app.
///
/// Call `sendNodesToWatch()` whenever node data changes (e.g., after
/// receiving position updates from the radio).
final class WatchSessionManager: NSObject, ObservableObject {

	static let shared = WatchSessionManager()

	private let logger = Logger(subsystem: "gvh.MeshtasticClient", category: "⌚ Watch")
	private var session: WCSession?
	private var watchUpdateTask: Task<Void, Never>?
	private var lastWatchSendTime: Date = .distantPast
	/// Minimum interval between Watch updates (seconds)
	private static let watchUpdateInterval: TimeInterval = 60

	override init() {
		super.init()
		guard WCSession.isSupported() else {
			logger.info("WCSession not supported on this device")
			return
		}
		let session = WCSession.default
		session.delegate = self
		session.activate()
		self.session = session
		logger.info("WCSession activated on iOS")
	}

	// MARK: - Public API

	/// Whether a paired Watch with the Meshtastic app installed is available.
	var isWatchAvailable: Bool {
		guard let session, session.activationState == .activated else { return false }
		return session.isPaired && session.isWatchAppInstalled
	}

	/// Send a specific node to the Watch as a foxhunt target.
	/// The Watch will pin this node in its foxhunt list regardless of distance.
	func sendNodeForFoxhunt(_ nodeNum: Int64) {
		guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
			logger.warning("Cannot send foxhunt target – Watch not available")
			return
		}
		guard session.isReachable else {
			// Fall back to transferUserInfo when not reachable
			session.transferUserInfo(["foxhuntTarget": UInt32(nodeNum)])
			logger.info("Queued foxhunt target \(nodeNum) via transferUserInfo")
			return
		}
		session.sendMessage(["foxhuntTarget": UInt32(nodeNum)], replyHandler: nil) { error in
			Task { @MainActor in
				self.logger.error("Failed to send foxhunt target: \(error.localizedDescription, privacy: .public)")
			}
		}
		logger.info("Sent foxhunt target \(nodeNum) to Watch")
	}

	/// Throttled: schedules a Watch update at most once per 60 seconds.
	func sendNodesToWatch() {
		guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
			return
		}

		// If we sent recently, coalesce into a single deferred send
		let now = Date()
		if now.timeIntervalSince(lastWatchSendTime) < Self.watchUpdateInterval {
			if watchUpdateTask == nil {
				watchUpdateTask = Task { @MainActor in
					let delay = Self.watchUpdateInterval - Date().timeIntervalSince(self.lastWatchSendTime)
					if delay > 0 {
						try? await Task.sleep(for: .seconds(delay))
					}
					guard !Task.isCancelled else { return }
					self.performSendNodesToWatch()
					self.watchUpdateTask = nil
				}
			}
			return
		}

		Task { @MainActor in
			self.performSendNodesToWatch()
		}
	}

	@MainActor
	private func performSendNodesToWatch() {
		lastWatchSendTime = Date()

		let nodes = fetchNodesForWatch()
		guard !nodes.isEmpty else { return }

		do {
			let data = try JSONEncoder().encode(nodes)
			try session?.updateApplicationContext(["nodes": data])
			logger.info("Sent \(nodes.count) nodes to Watch via applicationContext")
		} catch {
			logger.error("Failed to send nodes to Watch: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - SwiftData → Watch Node Serialization

	/// Maximum distance in meters to include a node (0.5 miles).
	private static let maxDistanceMeters: Double = 804.672

	@MainActor
	private func fetchNodesForWatch() -> [WatchNode] {
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.user != nil }
		)

		guard let userLocation = LocationsHandler.shared.locationsArray.last else {
			logger.info("No user location available, skipping Watch update")
			return []
		}

		do {
			let results = try context.fetch(descriptor)
			return results.compactMap { nodeInfo -> WatchNode? in
				WatchNode.make(from: nodeInfo, userLocation: userLocation, maxDistanceMeters: Self.maxDistanceMeters)
			}
		} catch {
			logger.error("Failed to fetch nodes for Watch: \(error.localizedDescription, privacy: .public)")
			return []
		}
	}
}

// MARK: - WCSessionDelegate
extension WatchSessionManager: WCSessionDelegate {

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		if let error {
			logger.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
		} else {
			logger.info("WCSession activated (state=\(activationState.rawValue))")
		}
	}

	func sessionDidBecomeInactive(_ session: WCSession) {
		logger.info("WCSession became inactive")
	}

	func sessionDidDeactivate(_ session: WCSession) {
		logger.info("WCSession deactivated – reactivating")
		session.activate()
	}

	func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
		if message["request"] as? String == "refreshNodes" {
			logger.info("Watch requested node refresh")
			sendNodesToWatch()
		}
	}
}

// MARK: - WatchNode (mirrors the Watch app's MeshNode, Codable for transfer)
struct WatchNode: Codable {
	let num: UInt32
	let longName: String
	let shortName: String
	let latitude: Double?
	let longitude: Double?
	let altitude: Int32?
	let lastPositionTime: Date?
	let lastHeard: Date?
	let snr: Float?

	static func make(from nodeInfo: NodeInfoEntity, userLocation: CLLocation, maxDistanceMeters: Double) -> WatchNode? {
		guard let user = nodeInfo.user else { return nil }
		guard let pos = nodeInfo.latestPosition else { return nil }

		let latI = pos.latitudeI
		let lonI = pos.longitudeI
		guard latI != 0, lonI != 0 else { return nil }

		let latitude = Double(latI) / 1e7
		let longitude = Double(lonI) / 1e7
		let nodeLocation = CLLocation(latitude: latitude, longitude: longitude)
		guard userLocation.distance(from: nodeLocation) <= maxDistanceMeters else { return nil }

		return WatchNode(
			num: UInt32(nodeInfo.num),
			longName: user.longName ?? "Unknown",
			shortName: user.shortName ?? "?",
			latitude: latitude,
			longitude: longitude,
			altitude: pos.altitude,
			lastPositionTime: pos.time,
			lastHeard: nodeInfo.lastHeard,
			snr: nodeInfo.snr != 0 ? nodeInfo.snr : nil
		)
	}
}
