//
//  MeshTVMapView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Fresh, minimal MKMapView wrapper for tvOS. Deliberately does NOT port the iOS
//  `ClusterMapView` (welded to touch gestures, MKUserTrackingButton and SwiftData).
//  No device GPS on tvOS, so `showsUserLocation` is off and we only plot the
//  reported positions of other nodes. Selection is driven by the focus engine
//  (clicking a pin) and by the side list via `selectedNodeNum`.
//

import MapKit
import SwiftUI

/// MKAnnotation for a mesh node. `num` lets us diff annotations without rebuilding.
final class NodeAnnotation: NSObject, MKAnnotation {
	let num: UInt32
	dynamic var coordinate: CLLocationCoordinate2D
	var title: String?
	var subtitle: String?

	init(node: MeshNode, coordinate: CLLocationCoordinate2D) {
		self.num = node.num
		self.coordinate = coordinate
		self.title = node.displayName
		self.subtitle = node.shortName
	}
}

struct MeshTVMapView: UIViewRepresentable {
	let nodes: [MeshNode]
	@Binding var selectedNodeNum: UInt32?

	func makeCoordinator() -> Coordinator { Coordinator(self) }

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator
		mapView.showsUserLocation = false          // no GPS on tvOS
		mapView.mapType = .standard
		mapView.register(
			MKMarkerAnnotationView.self,
			forAnnotationViewWithReuseIdentifier: Coordinator.reuseID
		)
		context.coordinator.applyInitialRegion(mapView, nodes: nodes)
		return mapView
	}

	func updateUIView(_ mapView: MKMapView, context: Context) {
		context.coordinator.parent = self
		context.coordinator.sync(mapView, nodes: nodes)
		context.coordinator.applyInitialRegion(mapView, nodes: nodes)
		context.coordinator.applySelection(mapView, selectedNodeNum: selectedNodeNum)
	}

	// MARK: - Coordinator

	final class Coordinator: NSObject, MKMapViewDelegate {
		static let reuseID = "meshNode"
		var parent: MeshTVMapView
		private var didSetInitialRegion = false
		private var annotationsByNum: [UInt32: NodeAnnotation] = [:]

		init(_ parent: MeshTVMapView) {
			self.parent = parent
		}

		/// Diff the annotation set against `nodes` (add / update coordinate / remove),
		/// keyed by node number so we don't churn the whole map each update.
		func sync(_ mapView: MKMapView, nodes: [MeshNode]) {
			let located = nodes.filter { $0.hasLocation }
			let incoming = Set(located.map { $0.num })

			// Remove annotations for nodes that are gone.
			for (num, annotation) in annotationsByNum where !incoming.contains(num) {
				mapView.removeAnnotation(annotation)
				annotationsByNum[num] = nil
			}

			// Add or update the rest.
			for node in located {
				guard let coordinate = node.coordinate else { continue }
				if let existing = annotationsByNum[node.num] {
					if existing.coordinate.latitude != coordinate.latitude ||
						existing.coordinate.longitude != coordinate.longitude {
						existing.coordinate = coordinate
					}
					existing.title = node.displayName
					existing.subtitle = node.shortName
				} else {
					let annotation = NodeAnnotation(node: node, coordinate: coordinate)
					annotationsByNum[node.num] = annotation
					mapView.addAnnotation(annotation)
				}
			}
		}

		/// Frame the located nodes once, when we first have something to show.
		/// No device GPS, so we center on the centroid of reported positions.
		func applyInitialRegion(_ mapView: MKMapView, nodes: [MeshNode]) {
			guard !didSetInitialRegion else { return }
			let coords = nodes.compactMap { $0.coordinate }
			guard !coords.isEmpty else { return }
			didSetInitialRegion = true

			let lats = coords.map(\.latitude)
			let lons = coords.map(\.longitude)
			let minLat = lats.min()!, maxLat = lats.max()!
			let minLon = lons.min()!, maxLon = lons.max()!
			let center = CLLocationCoordinate2D(
				latitude: (minLat + maxLat) / 2,
				longitude: (minLon + maxLon) / 2
			)
			let span = MKCoordinateSpan(
				latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
				longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
			)
			mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
		}

		/// Center on and select the annotation chosen from the side list.
		func applySelection(_ mapView: MKMapView, selectedNodeNum: UInt32?) {
			guard let num = selectedNodeNum, let annotation = annotationsByNum[num] else { return }
			if mapView.selectedAnnotations.first as? NodeAnnotation !== annotation {
				mapView.setCenter(annotation.coordinate, animated: true)
				mapView.selectAnnotation(annotation, animated: true)
			}
		}

		// MARK: MKMapViewDelegate

		func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
			guard annotation is NodeAnnotation else { return nil }
			let view = mapView.dequeueReusableAnnotationView(
				withIdentifier: Coordinator.reuseID,
				for: annotation
			) as? MKMarkerAnnotationView
			view?.clusteringIdentifier = "meshNode"
			view?.animatesWhenAdded = true
			view?.canShowCallout = true
			return view
		}

		func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
			if let node = view.annotation as? NodeAnnotation {
				parent.selectedNodeNum = node.num
			}
		}
	}
}
