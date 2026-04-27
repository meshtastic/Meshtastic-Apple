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
					let color: Color = node.neighborType == "direct" ? .green : .blue

					Annotation(
						node.shortName.isEmpty ? "Node \(node.nodeNum)" : node.shortName,
						coordinate: coord
					) {
						Image(systemName: node.iconName)
							.foregroundStyle(color)
							.font(.title3)
							.padding(4)
							.background(color.opacity(0.2))
							.clipShape(Circle())
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
			.mapControls {
				MapUserLocationButton(scope: mapScope)
				MapCompass(scope: mapScope)
				MapScaleView(scope: mapScope)
			}

			// Radar sweep overlay during active dwell
			RadarSweepView(isActive: isScanning)
		}
	}
}
