//
//  SpatialRouteSnapshot.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import OSLog
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
	let originName: String
	let targetName: String
	/// When the response arrived, or when the request was sent if that is all there is.
	let time: Date?
	let hopsTowards: Int
	/// Nil when the response didn't carry a return path.
	let hopsBack: Int?
	let forward: [Point]
	let back: [Point]
	/// The styled legs, endpoints and numbered relays drawn once the route is picked.
	var layout: SpatialRouteLayout = .empty
	var hasPath: Bool { forward.count >= 2 }

	/// Where each node on the route was when it was traced.
	var pointsByNum: [Int64: Point] {
		var points: [Int64: Point] = [:]
		for point in forward + back where points[point.num] == nil { points[point.num] = point }
		return points
	}
}

/// What a trace route shows in the spatial map's trace route menu: who traced whom, then its hops
/// and when it came back, e.g. "Base → Ridge" over "3 Hops · 2 h ago".
struct SpatialRouteMenuEntry: Equatable {
	let title: String
	let subtitle: String

	private static let relativeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.dateTimeStyle = .named
		formatter.unitsStyle = .full
		return formatter
	}()

	init(route: SpatialRouteSnapshot, now: Date = .now) {
		title = "\(route.originName) → \(route.targetName)"
		let card = TraceRouteCardModel(title: nil, date: route.time, state: .complete, hopsTowards: route.hopsTowards, hopsBack: route.hopsBack, roundTrip: nil)
		var hops = card.summary
		if route.hopsBack == nil {
			hops = String(localized: "\(hops), no return", comment: "Spatial map trace route menu: the response carried no return path, e.g. \"3 Hops, no return\"")
		}
		if let time = route.time {
			// A clock a little ahead of this device's reads as "now", not "in 2 minutes".
			let when = Self.relativeFormatter.localizedString(for: min(time, now), relativeTo: now)
			subtitle = String(localized: "\(hops) · \(when)", comment: "Spatial map trace route menu: hops, then when the route came back, e.g. \"3 Hops · 2 hours ago\"")
		} else {
			subtitle = hops
		}
	}
}

/// Reads the trace route menu's routes on a background context, so paging through a long route
/// history never holds up the main actor. Create it off the main thread: a model actor created on
/// the main thread runs its work there.
@ModelActor
actor SpatialRouteReader {
	func routes() -> [SpatialRouteSnapshot] {
		SpatialRouteSource.routes(context: modelContext)
	}

	/// Creates a reader off the main thread and reads the routes with it.
	nonisolated static func routes(container: ModelContainer) async -> [SpatialRouteSnapshot] {
		await Task.detached(priority: .utility) {
			await SpatialRouteReader(modelContainer: container).routes()
		}.value
	}
}

enum SpatialRouteSource {
	/// How many routes the toolbar's trace route menu lists.
	static let routeLimit = 20

	/// The newest routes that came back with positions, newest first.
	static func routes(context: ModelContext) -> [SpatialRouteSnapshot] {
		var descriptor = FetchDescriptor<TraceRouteEntity>(
			predicate: #Predicate<TraceRouteEntity> { $0.hasPositions == true && $0.response == true },
			sortBy: [SortDescriptor(\.time, order: .reverse)]
		)
		// A route counts as having positions when one node has one, but drawing it needs two, so
		// some routes drop out below. Fetch a page at a time until the menu is full or none are left.
		let pageSize = routeLimit * 3
		descriptor.fetchLimit = pageSize
		var fetched = 0
		var drawable: [(route: TraceRouteEntity, hops: [TraceRouteHopEntity])] = []
		while drawable.count < routeLimit {
			descriptor.fetchOffset = fetched
			let page = (try? context.fetch(descriptor)) ?? []
			fetched += page.count
			for route in page {
				// A route whose hops won't read is left out, like one that can't be drawn.
				guard let hops = hops(of: route, context: context) else { continue }
				if isDrawable(route, hops: hops) { drawable.append((route, hops)) }
			}
			if page.count < pageSize { break }
		}
		let originNums = Array(Set(drawable.map(\.route.fromNum)))
		let origins = (try? context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { originNums.contains($0.num) }))) ?? []
		let names = Dictionary(origins.compactMap { node in node.user?.longName.map { (node.num, $0) } }, uniquingKeysWith: { first, _ in first })
		return Array(newestFirst(drawable.compactMap { snapshot($0.route, hops: $0.hops, originName: names[$0.route.fromNum]) }).prefix(routeLimit))
	}

	/// The route's hops as the store has them now. Not `route.hops`: hearing a route again rebuilds
	/// its hops in the ingest context, which this one never hears about, and reading a hop it
	/// deleted traps. A fetch only returns hops that are still there, with their values loaded.
	/// Nil if the fetch fails, which is logged; an empty list is a route with no hops.
	static func hops(of route: TraceRouteEntity, context: ModelContext) -> [TraceRouteHopEntity]? {
		let routeID = route.persistentModelID
		let descriptor = FetchDescriptor<TraceRouteHopEntity>(predicate: #Predicate { $0.traceRoute?.persistentModelID == routeID })
		do {
			return try context.fetch(descriptor)
		} catch {
			Logger.data.error("🗺️ [Spatial] Couldn't read the hops of trace route \(route.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// Whether at least two nodes on the route's forward path have a position, the least the map
	/// can draw. Cheaper than building the snapshot.
	static func isDrawable(_ route: TraceRouteEntity, hops: [TraceRouteHopEntity]) -> Bool {
		let byNum = route.nodePositionsByNum
		return hops.lazy.filter { !$0.back && byNum[$0.num]?.coordinate != nil }.prefix(2).count == 2
	}

	/// One stored route as the map draws it, or nil when fewer than two of its nodes have a position.
	/// `hops` are the route's hops from `hops(of:context:)`.
	static func snapshot(_ route: TraceRouteEntity, hops: [TraceRouteHopEntity], originName: String?) -> SpatialRouteSnapshot? {
		let byNum = route.nodePositionsByNum
		func point(_ num: Int64, snr: Float) -> Point? {
			guard let position = byNum[num], let coordinate = position.coordinate else { return nil }
			return Point(num: num, coordinate: coordinate, altitude: Double(position.altitude), snr: snr)
		}
		let forwardHops = hops.filter { !$0.back }.sorted { $0.index < $1.index }
		let forward = forwardHops.compactMap { point($0.num, snr: $0.snr) }
		let backHops = hops.filter { $0.back }.sorted { $0.index < $1.index }
		var back: [Point] = []
		if let last = backHops.last {
			back = ([point(route.toNum, snr: 0)] + backHops.map { point($0.num, snr: $0.snr) } + [point(route.fromNum, snr: last.snr)]).compactMap { $0 }
		}
		guard forward.count >= 2 else { return nil }
		// The preset only grades signal quality, which the layout doesn't use.
		let legs = TraceRouteLegs(route: route, hops: hops, preset: .longFast, lookup: { _ in nil })
		let layout = SpatialRouteLayout(legs: legs, positions: byNum.compactMapValues { $0.coordinate })
		return SpatialRouteSnapshot(
			id: route.id, fromNum: route.fromNum, toNum: route.toNum,
			originName: originName ?? route.fromNum.toHex(),
			targetName: route.node?.user?.longName ?? route.toNum.toHex(),
			time: route.time ?? route.sentAt,
			hopsTowards: Int(route.hopsTowards),
			hopsBack: route.hopsBack >= 0 ? Int(route.hopsBack) : nil,
			forward: forward, back: back, layout: layout
		)
	}

	/// Newest first by when the route came back; routes with no time go last.
	static func newestFirst(_ routes: [SpatialRouteSnapshot]) -> [SpatialRouteSnapshot] {
		routes.sorted { a, b in
			let timeA = a.time ?? .distantPast, timeB = b.time ?? .distantPast
			return timeA != timeB ? timeA > timeB : a.id > b.id
		}
	}

	typealias Point = SpatialRouteSnapshot.Point
}
