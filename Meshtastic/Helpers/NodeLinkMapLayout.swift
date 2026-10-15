//
//  NodeLinkMapLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import CoreLocation
import MapKit

/// Where the SNR pills for a set of node links go on the map. Each known direction gets a pill
/// near the node that measured it. Thinned by zoom the same way as trace route labels.
struct NodeLinkMapLayout {

	struct Label {
		let id: String
		let snr: Float
		let coordinate: CLLocationCoordinate2D
		/// Link length in map points, used to decide whether the pill fits.
		let length: Double
		let opacity: Double
	}

	/// How far along the link, from the measuring node, its pill sits.
	static let labelFraction = 0.3

	let labels: [Label]

	/// `links` should be newest first, so the freshest pills win when they crowd each other.
	init(links: [NodeLink]) {
		var labels: [Label] = []
		for link in links {
			let pointA = MKMapPoint(link.coordinateA), pointB = MKMapPoint(link.coordinateB)
			let length = TraceRouteMapLayout.distance(pointA, pointB)
			// Each pill fades with its own direction's age, so a stale reading looks stale.
			if let snr = link.snrAtA {
				labels.append(Label(id: "\(link.id)-a", snr: snr, coordinate: Self.point(from: pointA, to: pointB).coordinate, length: length, opacity: link.opacityAtA))
			}
			if let snr = link.snrAtB {
				labels.append(Label(id: "\(link.id)-b", snr: snr, coordinate: Self.point(from: pointB, to: pointA).coordinate, length: length, opacity: link.opacityAtB))
			}
		}
		self.labels = labels
	}

	/// Pills whose link is long enough on screen to hold them, thinned so they don't overlap.
	func visibleLabels(in rect: MKMapRect) -> [Label] {
		let minLength = rect.width * TraceRouteMapLayout.labelMinSegmentFraction
		let long = labels.filter { $0.length >= minLength }
		return TraceRouteMapLayout.thinned(long, coordinate: \.coordinate, minDistance: rect.width * TraceRouteMapLayout.labelMinSeparationFraction)
	}

	private static func point(from start: MKMapPoint, to end: MKMapPoint) -> MKMapPoint {
		MKMapPoint(x: start.x + (end.x - start.x) * labelFraction, y: start.y + (end.y - start.y) * labelFraction)
	}
}
