// MARK: DiscoveryMapView
//
//  DiscoveryMapView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import MapKit
import SwiftData
import SwiftUI

struct DiscoveryMapView: View {
	let discoveredNodes: [DiscoveredNodeEntity]
	let userLatitude: Double
	let userLongitude: Double
	var isScanning: Bool = false

	@Namespace private var mapScope
	@State private var mapPosition: MapCameraPosition = .automatic

	private var userCoordinate: CLLocationCoordinate2D? {
		guard userLatitude != 0.0 || userLongitude != 0.0 else { return nil }
		return CLLocationCoordinate2D(latitude: userLatitude, longitude: userLongitude)
	}

	private var nodesWithPosition: [DiscoveredNodeEntity] {
		discoveredNodes.filter { $0.latitude != 0.0 || $0.longitude != 0.0 }
	}

	/// Compute a camera region that fits all nodes inside the radar circle.
	/// The radar circle uses min(width, height) / 2. Since the map is wider
	/// than it is tall (landscape-ish frame), the circle radius is based on
	/// the height. We add ~30 % extra span so nodes sit comfortably inside
	/// the circle rather than at its edge.
	private var fittedRegion: MKCoordinateRegion? {
		guard let userCoord = userCoordinate, !nodesWithPosition.isEmpty else { return nil }

		var maxLat = userCoord.latitude
		var minLat = userCoord.latitude
		var maxLon = userCoord.longitude
		var minLon = userCoord.longitude

		for node in nodesWithPosition {
			maxLat = max(maxLat, node.latitude)
			minLat = min(minLat, node.latitude)
			maxLon = max(maxLon, node.longitude)
			minLon = min(minLon, node.longitude)
		}

		let latSpan = (maxLat - minLat) * 1.6
		let lonSpan = (maxLon - minLon) * 1.6

		// Minimum span so the map doesn't zoom in too far with a single nearby node
		let clampedLatSpan = max(latSpan, 0.005)
		let clampedLonSpan = max(lonSpan, 0.005)

		let centerLat = (maxLat + minLat) / 2
		let centerLon = (maxLon + minLon) / 2

		return MKCoordinateRegion(
			center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
			span: MKCoordinateSpan(latitudeDelta: clampedLatSpan, longitudeDelta: clampedLonSpan)
		)
	}

	var body: some View {
		ZStack {
			Map(position: $mapPosition, scope: mapScope) {
				// User position
				if let userCoord = userCoordinate {
					Annotation("You", coordinate: userCoord) {
						Image(systemName: "person.circle.fill")
							.foregroundStyle(.orange)
							.font(.title2)
					}
				}

				// Discovered node annotations
				ForEach(nodesWithPosition, id: \.nodeNum) { node in
					let coord = CLLocationCoordinate2D(latitude: node.latitude, longitude: node.longitude)
					let nodeColor = Color(UIColor(hex: UInt32(node.nodeNum)))

					Annotation("", coordinate: coord) {
						VStack(spacing: 2) {
							CircleText(
								text: node.shortName.isEmpty ? String(node.nodeNum.toHex().suffix(4)) : node.shortName,
								color: nodeColor,
								circleSize: 30
							)
							Image(systemName: node.iconName)
								.font(.caption2)
								.foregroundStyle(nodeColor)
						}
					}
				}

				// Topology polylines to direct neighbors
				if let userCoord = userCoordinate {
					ForEach(nodesWithPosition.filter { $0.neighborType == "direct" }, id: \.nodeNum) { node in
						let nodeCoord = CLLocationCoordinate2D(latitude: node.latitude, longitude: node.longitude)
						MapPolyline(coordinates: [userCoord, nodeCoord])
							.stroke(.green.opacity(0.5), lineWidth: 2)
					}
				}
			}
			.mapScope(mapScope)
			.mapStyle(.standard(elevation: .realistic))
			.safeAreaPadding(.vertical, 20)
			.mapControls {
				MapUserLocationButton(scope: mapScope)
				MapCompass(scope: mapScope)
				MapScaleView(scope: mapScope)
			}

			// Radar sweep overlay during active dwell
			RadarSweepView(isActive: isScanning)
		}
		.onChange(of: nodesWithPosition.count) {
			if let region = fittedRegion {
				withAnimation(.easeInOut(duration: 0.8)) {
					mapPosition = .region(region)
				}
			}
		}
	}
}
