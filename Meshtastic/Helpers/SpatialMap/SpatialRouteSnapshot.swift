//
//  SpatialRouteSnapshot.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import SwiftData

/// A stored traceroute reduced to the two paths the spatial map draws and flies.
struct SpatialRouteSnapshot: Identifiable, Equatable, Sendable {
	struct Point: Equatable, Sendable {
		let num: Int64
		let coordinate: CLLocationCoordinate2D
		let altitude: Double
		/// SNR heard at this node, 0 for the first point of a path.
		let snr: Float
		static func == (lhs: Self, rhs: Self) -> Bool {
			lhs.num == rhs.num && lhs.snr == rhs.snr && lhs.altitude == rhs.altitude
				&& lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
		}
	}

	let id: Int64
	let fromNum: Int64
	let toNum: Int64
	let targetName: String
	let time: Date?
	let forward: [Point]
	let back: [Point]
	var hasPath: Bool { forward.count >= 2 }
}

/// One node-to-node link seen in a traceroute, with the latest SNR heard in each direction.
struct SpatialLinkSnapshot: Identifiable, Equatable, Sendable {
	let a: Int64
	let b: Int64
	var snrAtoB: Float?
	var snrBtoA: Float?
	var id: String { "\(a)-\(b)" }
}

@MainActor
enum SpatialRouteSource {
	static let routeLimit = 150

	static func routes(context: ModelContext) -> [SpatialRouteSnapshot] {
		var descriptor = FetchDescriptor<TraceRouteEntity>(
			predicate: #Predicate<TraceRouteEntity> { $0.hasPositions == true && $0.response == true },
			sortBy: [SortDescriptor(\.time, order: .reverse)]
		)
		descriptor.fetchLimit = routeLimit
		let routes = (try? context.fetch(descriptor)) ?? []
		return routes.compactMap { route in
			let byNum = route.nodePositionsByNum
			func point(_ num: Int64, snr: Float) -> Point? {
				guard let position = byNum[num], let coordinate = position.coordinate else { return nil }
				return Point(num: num, coordinate: coordinate, altitude: Double(position.altitude), snr: snr)
			}
			let forwardHops = route.hops.filter { !$0.back }.sorted { $0.index < $1.index }
			let forward = forwardHops.compactMap { point($0.num, snr: $0.snr) }
			let backHops = route.hops.filter { $0.back }.sorted { $0.index < $1.index }
			var back: [Point] = []
			if let last = backHops.last {
				back = ([point(route.toNum, snr: 0)] + backHops.map { point($0.num, snr: $0.snr) } + [point(route.fromNum, snr: last.snr)]).compactMap { $0 }
			}
			guard forward.count >= 2 else { return nil }
			let name = route.node?.user?.longName ?? route.toNum.toHex()
			return SpatialRouteSnapshot(id: route.id, fromNum: route.fromNum, toNum: route.toNum, targetName: name, time: route.time, forward: forward, back: back)
		}
	}

	typealias Point = SpatialRouteSnapshot.Point

	/// Every node-to-node link the routes crossed, the latest SNR kept per direction.
	nonisolated static func links(from routes: [SpatialRouteSnapshot]) -> [SpatialLinkSnapshot] {
		var links: [String: SpatialLinkSnapshot] = [:]
		var seen: [String: Date] = [:]
		for route in routes.sorted(by: { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }) {
			for path in [route.forward, route.back] where path.count >= 2 {
				for i in 0..<(path.count - 1) {
					let from = path[i].num, to = path[i + 1].num
					guard from != to, from != 0, to != 0, from != MeshPacketEvent.broadcastNum, to != MeshPacketEvent.broadcastNum else { continue }
					let a = min(from, to), b = max(from, to)
					let key = "\(a)-\(b)"
					var link = links[key] ?? SpatialLinkSnapshot(a: a, b: b, snrAtoB: nil, snrBtoA: nil)
					let heardAt = path[i + 1].snr
					let directionKey = key + (from == a ? ">" : "<")
					if seen[directionKey] == nil {
						seen[directionKey] = route.time ?? .distantPast
						if from == a { link.snrAtoB = heardAt } else { link.snrBtoA = heardAt }
					}
					links[key] = link
				}
			}
		}
		return links.values.sorted { $0.id < $1.id }
	}
}
