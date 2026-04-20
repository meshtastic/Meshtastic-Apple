//
//  PhoneConnectivityManager.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import WatchConnectivity
import os

/// Receives mesh node data from the companion iOS app via WatchConnectivity.
///
/// The iOS app pushes node updates using `updateApplicationContext(_:)`.
/// The watch can also request a refresh by sending a message.
@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {

	// MARK: - Published state

	/// All mesh nodes received from the phone, keyed by node number.
	@Published var nodes: [UInt32: MeshNode] = [:]

	/// Whether the companion iPhone is reachable right now.
	@Published var isPhoneReachable = false

	/// Whether we have received at least one update from the phone.
	@Published var hasReceivedData = false

	/// Node numbers pinned as foxhunt targets from the iOS app.
	@Published var foxhuntTargets: Set<UInt32> = []

	// MARK: - Private

	private let logger = Logger(subsystem: "gvh.MeshtasticClient.watchkitapp", category: "📱 Phone")
	private var session: WCSession?

	// MARK: - Lifecycle

	override init() {
		super.init()
		guard WCSession.isSupported() else {
			logger.warning("WCSession is not supported on this device")
			return
		}
		let session = WCSession.default
		session.delegate = self
		session.activate()
		self.session = session
		logger.info("WCSession activated")
	}

	// MARK: - Public API

	/// Ask the phone to send fresh node data.
	func requestRefresh() {
		guard let session, session.isReachable else {
			logger.warning("Cannot request refresh – phone not reachable")
			return
		}
		session.sendMessage(["request": "refreshNodes"], replyHandler: nil) { error in
			Task { @MainActor in
				self.logger.error("Failed to request refresh: \(error.localizedDescription, privacy: .public)")
			}
		}
		logger.info("Requested node refresh from phone")
	}

	// MARK: - Decoding

	private func decodeNodes(from context: [String: Any]) {
		// Handle foxhunt target messages
		if let targetNum = context["foxhuntTarget"] as? UInt32 {
			foxhuntTargets.insert(targetNum)
			logger.info("Added foxhunt target: \(targetNum)")
			return
		}

		guard let data = context["nodes"] as? Data else {
			logger.warning("No 'nodes' key in application context")
			return
		}
		do {
			let decoded = try JSONDecoder().decode([MeshNode].self, from: data)
			var nodeDict: [UInt32: MeshNode] = [:]
			for node in decoded {
				nodeDict[node.num] = node
			}
			nodes = nodeDict
			hasReceivedData = true
			logger.info("Decoded \(decoded.count) nodes from phone")
		} catch {
			logger.error("Failed to decode nodes: \(error.localizedDescription, privacy: .public)")
		}
	}
}

// MARK: - WCSessionDelegate
extension PhoneConnectivityManager: @preconcurrency WCSessionDelegate {

	nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		Task { @MainActor in
			if let error {
				logger.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
			} else {
				logger.info("WCSession activation complete (state=\(activationState.rawValue))")
				isPhoneReachable = session.isReachable

				// Load any existing application context
				if !session.receivedApplicationContext.isEmpty {
					decodeNodes(from: session.receivedApplicationContext)
				}
			}
		}
	}

	nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
		Task { @MainActor in
			isPhoneReachable = session.isReachable
			logger.info("Phone reachability changed: \(session.isReachable)")
			if session.isReachable && !hasReceivedData {
				requestRefresh()
			}
		}
	}

	nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
		Task { @MainActor in
			decodeNodes(from: applicationContext)
		}
	}

	nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
		Task { @MainActor in
			decodeNodes(from: userInfo)
		}
	}

	nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
		Task { @MainActor in
			decodeNodes(from: message)
		}
	}
}
