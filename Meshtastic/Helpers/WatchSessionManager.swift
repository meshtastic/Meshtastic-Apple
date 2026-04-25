//
//  WatchSessionManager.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import WatchConnectivity
import CoreData
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

	/// Fetch nodes from Core Data and push them to the Watch via application context.
	func sendNodesToWatch() {
		guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
			return
		}

		let context = PersistenceController.shared.container.viewContext
		context.perform { [weak self] in
			guard let self else { return }
			let nodes = self.fetchNodesForWatch(context: context)
			guard !nodes.isEmpty else { return }

			do {
				let data = try JSONEncoder().encode(nodes)
				try session.updateApplicationContext(["nodes": data])
				self.logger.info("Sent \(nodes.count) nodes to Watch via applicationContext")
			} catch {
				self.logger.error("Failed to send nodes to Watch: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	// MARK: - Core Data → Watch Node Serialization

	private func fetchNodesForWatch(context: NSManagedObjectContext) -> [WatchNode] {
		let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "NodeInfoEntity")
		fetchRequest.predicate = NSPredicate(format: "user != nil")

		do {
			let results = try context.fetch(fetchRequest)
			return results.compactMap { nodeInfo -> WatchNode? in
				guard let user = nodeInfo.value(forKey: "user") as? NSManagedObject else { return nil }

				let num = nodeInfo.value(forKey: "num") as? Int64 ?? 0
				let longName = user.value(forKey: "longName") as? String ?? "Unknown"
				let shortName = user.value(forKey: "shortName") as? String ?? "?"
				let snr = nodeInfo.value(forKey: "snr") as? Float
				let lastHeard = nodeInfo.value(forKey: "lastHeard") as? Date

				// Get the latest position from the ordered set
				var latitude: Double?
				var longitude: Double?
				var altitude: Int32?
				var lastPositionTime: Date?

				if let positions = nodeInfo.value(forKey: "positions") as? NSOrderedSet {
					// Find the position marked as latest, or use the last one
					let posArray = positions.array as? [NSManagedObject] ?? []
					let latestPosition = posArray.first(where: {
						($0.value(forKey: "latest") as? Bool) == true
					}) ?? posArray.last

					if let pos = latestPosition {
						let latI = pos.value(forKey: "latitudeI") as? Int32 ?? 0
						let lonI = pos.value(forKey: "longitudeI") as? Int32 ?? 0
						if latI != 0, lonI != 0 {
							latitude = Double(latI) / 1e7
							longitude = Double(lonI) / 1e7
							altitude = pos.value(forKey: "altitude") as? Int32
							lastPositionTime = pos.value(forKey: "time") as? Date
						}
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
