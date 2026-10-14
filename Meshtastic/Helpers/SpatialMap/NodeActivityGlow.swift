//
//  NodeActivityGlow.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import Foundation

/// How brightly a node's halo shows on the spatial map: a base level from when it was last heard,
/// and a short boost each time a packet from it arrives.
enum NodeActivityGlow {
	enum Tier: Int, Comparable {
		case off, stale, recent, live
		static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
	}

	static let liveWindow: TimeInterval = 60
	static let recentWindow: TimeInterval = 15 * 60
	static let staleWindow: TimeInterval = 2 * 60 * 60
	static let boostDecay: TimeInterval = 1.5

	static func tier(lastHeard: Date?, now: Date) -> Tier {
		guard let lastHeard else { return .off }
		let age = now.timeIntervalSince(lastHeard)
		if age < liveWindow { return .live }
		if age < recentWindow { return .recent }
		if age < staleWindow { return .stale }
		return .off
	}

	static func baseOpacity(_ tier: Tier) -> Float {
		switch tier {
		case .off: 0
		case .stale: 0.12
		case .recent: 0.3
		case .live: 0.5
		}
	}

	/// A boost fades out exponentially; it is spent once it drops below `boostFloor`.
	static let boostFloor: Float = 0.02

	static func boost(startedAt start: TimeInterval, now: TimeInterval, initial: Float) -> Float {
		initial * Float(exp(-max(0, now - start) / boostDecay))
	}

	static func opacity(base: Float, boost: Float) -> Float { max(base, boost) }

	static func scale(boost: Float) -> Float { 1 + 0.4 * boost }
}
