//
//  TerrainTiming.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
import Foundation
import OSLog

/// How long a slow step of building terrain took, for the 3D map and the cinema's windows: logged
/// when it ends, and an interval in Instruments' os_signpost track while it runs.
struct TerrainTiming: Sendable {
	private static let signposter = OSSignposter(logger: .services)

	private let name: StaticString
	private let state: OSSignpostIntervalState
	private let started: ContinuousClock.Instant

	/// Starts timing a step; `name` labels its interval in Instruments.
	static func start(_ name: StaticString) -> TerrainTiming {
		TerrainTiming(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()), started: .now)
	}

	/// Ends the step and logs `message` with how long it took.
	func end(_ message: String) {
		Self.signposter.endInterval(name, state)
		let duration = ContinuousClock.now - started
		let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
		Logger.services.info("\(message, privacy: .public) in \(String(format: "%.2f", seconds), privacy: .public)s")
	}
}
