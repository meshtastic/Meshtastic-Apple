//
//  MapView.swift
//  MeshtasticClient
//
//  Created by Joshua Pirihi on 22/12/21.
//

import Foundation
import UIKit
import MapKit
import SwiftUI
import CoreData

struct MapView: UIViewRepresentable {
	//@Binding var route: MKPolyline?
	var nodes: FetchedResults<NodeInfoEntity>
	
	let mapViewDelegate = MapViewDelegate()

	func makeUIView(context: Context) -> MKMapView {
		let map = MKMapView(frame: .zero)
		map.userTrackingMode = .follow
		map.mapType = .satellite
		map.register(PositionAnnotationView.self, forAnnotationViewWithReuseIdentifier: NSStringFromClass(PositionAnnotationView.self))
		return map
	}

	func updateUIView(_ view: MKMapView, context: Context) {
		view.delegate = mapViewDelegate                          // (1) This should be set in makeUIView, but it is getting reset to `nil`
		view.translatesAutoresizingMaskIntoConstraints = false   // (2) In the absence of this, we get constraints error on rotation; and again, it seems one should do this in makeUIView, but has to be here
		//addRoute(to: view)
		showNodePositions(to: view)
	}
}

private extension MapView {
	//func addRoute(to view: MKMapView) {
	//	if !view.overlays.isEmpty {
	//		view.removeOverlays(view.overlays)
	//	}

		//guard let route = route else { return }
		//let mapRect = route.boundingMapRect
		//view.setVisibleMapRect(mapRect, edgePadding: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10), animated: true)
		//view.addOverlay(route)
	//}
	func showNodePositions(to view: MKMapView) {
		if !view.annotations.isEmpty {
			view.removeAnnotations(view.annotations)
		}
		
		for node in self.nodes {
			//try and get the last position
			if (node.positions?.count ?? 0) > 0 {
				let annotation = PositionAnnotation()
				annotation.coordinate = (node.positions!.lastObject as! PositionEntity).coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
				annotation.title = node.user?.longName ?? "Unknown"
				annotation.shortName = node.user?.shortName?.uppercased() ?? "???"
				
				view.addAnnotation(annotation)
			}
		}
	}
}

class MapViewDelegate: NSObject, MKMapViewDelegate {
	
	func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {

		guard !annotation.isKind(of: MKUserLocation.self) else {
			// Make a fast exit if the annotation is the `MKUserLocation`, as it's not an annotation view we wish to customize.
			return nil
		}
		
		var annotationView: MKAnnotationView?
		
		if let annotation = annotation as? PositionAnnotation {
			annotationView = self.setupPositionAnnotationView(for: annotation, on: mapView)
		}
		
		return annotationView
	}
	
	private func setupPositionAnnotationView(for annotation: PositionAnnotation, on mapView: MKMapView) -> PositionAnnotationView {
		let identifier = NSStringFromClass(PositionAnnotationView.self)

		let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? PositionAnnotationView ?? PositionAnnotationView()
		
		annotationView.name = annotation.shortName ?? "???"
		
		annotationView.canShowCallout = true
		
		
		return annotationView
	}
}
