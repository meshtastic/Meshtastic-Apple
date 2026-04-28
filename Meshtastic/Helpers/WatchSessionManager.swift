//
//  WatchSessionManager.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import WatchConnectivity
import SwiftData
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

	/// Fetch nodes from SwiftData and push them to the Watch via application context.
	func sendNodesToWatch() {
		guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
			return
		}

		Task { @MainActor in
			let nodes = fetchNodesForWatch()
			guard !nodes.isEmpty else { return }

			do {
				let data = try JSONEncoder().encode(nodes)
				try session.updateApplicationContext(["nodes": data])
				logger.info("Sent \(nodes.count) nodes to Watch via applicationContext")
			} catch {
				logger.error("Failed to send nodes to Watch: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	// MARK: - SwiftData → Watch Node Serialization

	@MainActor
	private func fetchNodesForWatch() -> [WatchNode] {
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate<NodeInfoEntity> { $0.user != nil }
		)

		do {
			let results = try context.fetch(descriptor)
			return results.compactMap { nodeInfo -> WatchNode? in
				guard let user = nodeInfo.user else { return nil }

				let num = nodeInfo.num
				let longName = user.longName ?? "Unknown"
				let shortName = user.shortName ?? "?"
				let snr: Float? = nodeInfo.snr != 0 ? nodeInfo.snr : nil
				let lastHeard = nodeInfo.lastHeard

				var latitude: Double?
				var longitude: Double?
				var altitude: Int32?
				var lastPositionTime: Date?

				let latestPosition = nodeInfo.positions.first(where: { $0.latest }) ?? nodeInfo.positions.last
				if let pos = latestPosition {
					let latI = pos.latitudeI
					let lonI = pos.longitudeI
					if latI != 0, lonI != 0 {
						latitude = Double(latI) / 1e7
						longitude = Double(lonI) / 1e7
						altitude = pos.altitude
						lastPositionTime = pos.time
					}
				}

				return WatchNode(
					num: UInt32(num),
					longName: longName,
					shortName: shortName,
					latitude: latitude,
					longitude: longitude,
					altitude: altitude,
					lastPositionTime: lastPositionTime,
					lastHeard: lastHeard,
					snr: snr
				)
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
}
