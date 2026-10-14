//
//  TraceRouteShareModelTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreLocation
import MapKit
import Testing
@testable import Meshtastic

/// Trace routes around Seattle for the share image tests.
enum TraceRouteShareFixtures {
	// The low three bytes are the node's color.
	static let origin: Int64 = 0x0A67_EA94
	static let ridge: Int64 = 0x33F2_A541
	static let gateway: Int64 = 0x55B4_7CFF
	static let harbor: Int64 = 0x7740_C4FF
	static let target: Int64 = 0x11FF_6B6B

	static let nodes: [Int64: TraceRouteLegs.NodeDetails] = [
		origin: .init(longName: "Capitol Hill Base", shortName: "CHB"),
		ridge: .init(longName: "Queen Anne Ridge", shortName: "QAR"),
		gateway: .init(longName: "Fremont Gateway", shortName: "FGW", viaMqtt: true),
		harbor: .init(longName: "Ballard Harbor", shortName: "BH"),
		target: .init(longName: "Golden Gardens Summit", shortName: "GGS")
	]

	static let positions: [Int64: CLLocationCoordinate2D] = [
		origin: CLLocationCoordinate2D(latitude: 47.6235, longitude: -122.3190),
		ridge: CLLocationCoordinate2D(latitude: 47.6370, longitude: -122.3570),
		gateway: CLLocationCoordinate2D(latitude: 47.6510, longitude: -122.3500),
		harbor: CLLocationCoordinate2D(latitude: 47.6680, longitude: -122.3840),
		target: CLLocationCoordinate2D(latitude: 47.6910, longitude: -122.4030)
	]

	static let date = Date(timeIntervalSince1970: 1_791_900_000)

	static func legs(
		forward: [TraceRouteLegs.Hop],
		back: [TraceRouteLegs.Hop],
		originBackSnr: Float = 6.25,
		hasBack: Bool = true,
		positions: [Int64: CLLocationCoordinate2D] = positions,
		nodes: [Int64: TraceRouteLegs.NodeDetails] = nodes
	) -> TraceRouteLegs {
		TraceRouteLegs(
			originNum: origin,
			targetNum: target,
			forwardHops: forward,
			backRelays: back,
			originBackSnr: originBackSnr,
			hasBack: hasBack,
			preset: .longFast,
			positions: positions,
			lookup: { nodes[$0] }
		)
	}

	/// Origin → ridge → gateway (MQTT) → harbor → target, back through harbor and ridge.
	static func model(
		positions: [Int64: CLLocationCoordinate2D] = positions,
		hasBack: Bool = true,
		roundTrip: TimeInterval? = 6.4
	) -> TraceRouteShareModel {
		let legs = legs(
			forward: [
				.init(num: origin, snr: 6.25), .init(num: ridge, snr: 9.5), .init(num: gateway, snr: -19.75),
				.init(num: harbor, snr: -24.0), .init(num: target, snr: 3.0)
			],
			back: [.init(num: harbor, snr: 1.25), .init(num: ridge, snr: -20.5)],
			hasBack: hasBack,
			positions: positions
		)
		return TraceRouteShareModel(
			legs: legs,
			positions: positions,
			date: date,
			observed: false,
			roundTrip: roundTrip,
			mapWidth: TraceRouteShareStyle.mapWidth
		)
	}

	/// A long route: eight relays out including an unknown repeater, seven back, long names.
	static func longModel(withPositions: Bool = true) -> TraceRouteShareModel {
		var nodes = nodes
		var positions = positions
		var forward: [TraceRouteLegs.Hop] = [.init(num: origin, snr: 5)]
		var back: [TraceRouteLegs.Hop] = []
		for index in 0..<8 {
			let num = Int64(0x2000_0000 + index * 0x0101_0F37)
			nodes[num] = .init(
				longName: index == 2 ? "Very Long Relay Name On The Hill \(index)" : "Relay \(index + 1) Station",
				shortName: "R\(index + 1)",
				viaMqtt: index == 5
			)
			positions[num] = CLLocationCoordinate2D(latitude: 47.60 + Double(index) * 0.012, longitude: -122.33 - Double(index % 3) * 0.02)
			let snrs: [Float] = [8, -18.5, -6, 11, -24.25, 0.75, -26, 4.5]
			forward.append(.init(num: index == 4 ? TraceRouteLegs.unknownRepeaterNum : num, snr: snrs[index]))
			if index != 3 {
				back.insert(.init(num: num, snr: snrs[(index + 3) % 8]), at: 0)
			}
		}
		nodes[target] = .init(longName: "Golden Gardens Summit Repeater 🏔️", shortName: "GGS")
		forward.append(.init(num: target, snr: -7.5))
		let legs = legs(forward: forward, back: back, positions: withPositions ? positions : [:], nodes: nodes)
		return TraceRouteShareModel(
			legs: legs,
			positions: withPositions ? positions : [:],
			date: date,
			observed: false,
			roundTrip: 21.75,
			mapWidth: TraceRouteShareStyle.mapWidth
		)
	}

	/// A direct route that was observed on the mesh: no relays, no round trip, no positions.
	static func directObservedModel() -> TraceRouteShareModel {
		let legs = legs(forward: [.init(num: origin, snr: 7.25), .init(num: target, snr: 10.5)], back: [], positions: [:])
		return TraceRouteShareModel(legs: legs, positions: [:], date: date, observed: true, roundTrip: nil, mapWidth: TraceRouteShareStyle.mapWidth)
	}
}

@Suite("Trace route share model")
struct TraceRouteShareModelTests {

	private typealias Fixtures = TraceRouteShareFixtures

	@Test("Hop counts are the relays in each direction")
	func hopCounts() {
		let model = Fixtures.model()
		#expect(model.hopsTowards == 3)
		#expect(model.hopsBack == 2)
		#expect(Fixtures.model(hasBack: false).hopsBack == nil)
		#expect(Fixtures.directObservedModel().hopsTowards == 0)
	}

	@Test("Best and worst legs cover both directions")
	func bestAndWorst() {
		let model = Fixtures.model()
		#expect(model.bestLeg?.snr == 9.5)
		#expect(model.bestLeg?.num == Fixtures.ridge)
		#expect(model.worstLeg?.snr == -24)
		#expect(model.worstLeg?.num == Fixtures.harbor)
	}

	@Test("Best and worst are nil when no SNR was reported")
	func noSnr() {
		let legs = Fixtures.legs(
			forward: [.init(num: Fixtures.origin, snr: 0), .init(num: Fixtures.target, snr: TraceRouteLegs.unknownSnr)],
			back: [],
			hasBack: false
		)
		let model = TraceRouteShareModel(legs: legs, positions: [:], date: nil, observed: false, roundTrip: nil, mapWidth: 320)
		#expect(model.bestLeg == nil)
		#expect(model.worstLeg == nil)
	}

	@Test("Route distance adds up the forward legs")
	func routeDistance() throws {
		let model = Fixtures.model()
		let expected = zip(model.legs.forward, model.legs.forward.dropFirst()).reduce(0.0) { total, pair in
			let from = Fixtures.positions[pair.0.num]!, to = Fixtures.positions[pair.1.num]!
			return total + CLLocation(latitude: from.latitude, longitude: from.longitude)
				.distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
		}
		let distance = try #require(model.routeDistance)
		#expect(abs(distance - expected) < 0.5)
		#expect(distance > 9_000 && distance < 15_000)
	}

	@Test("Route distance needs both endpoints to have a position")
	func routeDistanceNeedsEndpoints() {
		var positions = Fixtures.positions
		positions[Fixtures.target] = nil
		let model = Fixtures.model(positions: positions)
		#expect(model.map != nil)
		#expect(model.routeDistance == nil)
	}

	@Test("No map without two stops with a position")
	func noMap() {
		#expect(Fixtures.model(positions: [:]).map == nil)
		#expect(Fixtures.model(positions: [Fixtures.origin: Fixtures.positions[Fixtures.origin]!]).map == nil)
		#expect(Fixtures.model(positions: [:]).routeDistance == nil)
		#expect(Fixtures.directObservedModel().map == nil)
	}

	@Test("The map frames every positioned stop with a margin")
	func framing() throws {
		let map = try #require(Fixtures.model().map)
		#expect(map.size.width == TraceRouteShareStyle.mapWidth)
		for coordinate in Fixtures.positions.values {
			let point = map.point(for: coordinate)
			#expect(point.x > map.size.width * 0.1 && point.x < map.size.width * 0.9)
			#expect(point.y > map.size.height * 0.1 && point.y < map.size.height * 0.9)
		}
	}

	@Test("The map area matches the map's aspect ratio")
	func aspect() throws {
		let map = try #require(Fixtures.model().map)
		#expect(abs(map.rect.height / map.rect.width - map.size.height / map.size.width) < 0.01)
		let ratio = map.size.height / map.size.width
		#expect(TraceRouteShareModel.mapAspectRange.contains(ratio))
	}

	@Test("A route running east to west gets the flattest map")
	func flatRoute() {
		let points = [
			MKMapPoint(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.5)),
			MKMapPoint(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.1))
		]
		let frame = TraceRouteShareModel.frame(points: points, width: 300)
		#expect(frame.size.height == 225)
	}

	@Test("A route running north to south gets the tallest map")
	func tallRoute() {
		let points = [
			MKMapPoint(CLLocationCoordinate2D(latitude: 47.4, longitude: -122.3)),
			MKMapPoint(CLLocationCoordinate2D(latitude: 47.8, longitude: -122.3))
		]
		let frame = TraceRouteShareModel.frame(points: points, width: 300)
		#expect(frame.size.height == 300)
		// Widened, not cropped: both ends stay inside.
		#expect(frame.rect.contains(points[0]) && frame.rect.contains(points[1]))
	}

	@Test("A set height replaces the shape and keeps the route inside")
	func setHeight() {
		let points = [
			MKMapPoint(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.5)),
			MKMapPoint(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.1))
		]
		let frame = TraceRouteShareModel.frame(points: points, width: 300, height: 600)
		#expect(frame.size == CGSize(width: 300, height: 600))
		#expect(abs(frame.rect.height / frame.rect.width - 2) < 0.01)
		#expect(frame.rect.contains(points[0]) && frame.rect.contains(points[1]))
	}

	@Test("Fitting the map to a height keeps its width and never goes flatter than the range")
	func fittingMap() throws {
		let model = Fixtures.model()
		let map = try #require(model.map)
		let taller = try #require(model.fittingMap(height: map.size.height + 200).map)
		#expect(taller.size.width == map.size.width)
		#expect(taller.size.height == map.size.height + 200)
		#expect(Fixtures.positions.values.allSatisfy { taller.rect.contains(MKMapPoint($0)) })
		let flattest = (map.size.width * CGFloat(TraceRouteShareModel.mapAspectRange.lowerBound)).rounded(.up)
		#expect(model.fittingMap(height: 10).map?.size.height == flattest)
		#expect(Fixtures.model(positions: [:]).fittingMap(height: 500).map == nil)
	}

	@Test("Nodes close together still show the minimum span")
	func minimumSpan() {
		let center = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
		let points = [MKMapPoint(center), MKMapPoint(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.29995))]
		let frame = TraceRouteShareModel.frame(points: points, width: 300)
		let meters = frame.rect.width / MKMapPointsPerMeterAtLatitude(47.6)
		#expect(meters >= TraceRouteShareModel.mapMinimumSpanMeters - 1)
	}

	@Test("The plain text lists both directions")
	func plainText() {
		let text = Fixtures.model().plainText
		#expect(text.contains("Capitol Hill Base → Golden Gardens Summit"))
		#expect(text.contains("Capitol Hill Base → Queen Anne Ridge → Fremont Gateway → Ballard Harbor → Golden Gardens Summit"))
		#expect(text.contains("Golden Gardens Summit → Ballard Harbor → Queen Anne Ridge → Capitol Hill Base"))
		#expect(text.hasSuffix("meshtastic.org"))
		#expect(!Fixtures.model(hasBack: false).plainText.contains("Ballard Harbor → Queen Anne Ridge"))
	}

	@Test func shareFileNamesAreDistinctAndSafe() {
		let date = Date(timeIntervalSince1970: 1_791_000_000)
		let name = TraceRouteShareImage.fileName(origin: "CHB", destination: "GGS", date: date)
		#expect(name.hasPrefix("Trace Route CHB-GGS "))
		#expect(name.hasSuffix(".png"))
		let later = TraceRouteShareImage.fileName(origin: "CHB", destination: "GGS", date: date.addingTimeInterval(1))
		#expect(name != later, "a second later is a different file")
		let odd = TraceRouteShareImage.fileName(origin: "A/B", destination: "C:D", date: date)
		#expect(!odd.contains("/") && !odd.contains(":"))
		#expect(TraceRouteShareImage.fileName(origin: nil, destination: nil, date: date).hasPrefix("Trace Route 20"))
	}
}
