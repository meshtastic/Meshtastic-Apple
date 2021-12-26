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

//wrap a MKMapView into something we can use in SwiftUI
struct MapView: UIViewRepresentable {
	
	var nodes: FetchedResults<NodeInfoEntity>
	
	let mapViewDelegate = MapViewDelegate()
	
	//observe changes to the key in UserDefaults
	@AppStorage("meshMapType") var type: String = "hybrid"
	
	//@State var needToMoveToMeshRegion: Bool = true
	
	func makeUIView(context: Context) -> MKMapView {
		
		let map = MKMapView(frame: .zero)
		
		map.userTrackingMode = .follow
		
		let region = MKCoordinateRegion( center: map.centerCoordinate, latitudinalMeters: CLLocationDistance(exactly: 500)!, longitudinalMeters: CLLocationDistance(exactly: 500)!)
		map.setRegion(map.regionThatFits(region), animated: false)
		
		//self.updateMapType(map)
		self.showNodePositions(to: map)
		self.moveToMeshRegion(in: map)
		
		map.register(PositionAnnotationView.self, forAnnotationViewWithReuseIdentifier: NSStringFromClass(PositionAnnotationView.self))
		
		return map
	}

	func updateUIView(_ view: MKMapView, context: Context) {
		view.delegate = mapViewDelegate                          // (1) This should be set in makeUIView, but it is getting reset to `nil`
		view.translatesAutoresizingMaskIntoConstraints = false   // (2) In the absence of this, we get constraints error on rotation; and again, it seems one should do this in makeUIView, but has to be here
		
		self.updateMapType(view)
		
		self.showNodePositions(to: view)
		
		//if (self.needToMoveToMeshRegion) {
		//	self.moveToMeshRegion(in: view)
		//	self.needToMoveToMeshRegion = false
		//}
	}
	
	func moveToMeshRegion(in mapView: MKMapView) {
		//go through the annotations and create a bounding box that encloses them
		
		var minLat: CLLocationDegrees = 90.0
		var maxLat: CLLocationDegrees = -90.0
		var minLon: CLLocationDegrees = 180.0
		var maxLon: CLLocationDegrees = -180.0
		
		for annotation in mapView.annotations {
			if annotation.isKind(of: PositionAnnotation.self) {
				minLat = min(minLat, annotation.coordinate.latitude)
				maxLat = max(maxLat, annotation.coordinate.latitude)
				minLon = min(minLon, annotation.coordinate.longitude)
				maxLon = max(maxLon, annotation.coordinate.longitude)
			}
		}
		let centerCoord = CLLocationCoordinate2D(latitude: (minLat+maxLat)/2, longitude: (minLon+maxLon)/2)
		
		let span = MKCoordinateSpan(latitudeDelta: (maxLat-minLat)*1.5, longitudeDelta: (maxLon-minLon)*1.5)
		
		let region = mapView.regionThatFits(MKCoordinateRegion(center: centerCoord, span: span))
		
		mapView.setRegion(region, animated: true)
		
		
	}
	
	func updateMapType(_ map: MKMapView) {
		
		switch self.type {
		case "satellite":
			map.mapType = .satellite
			break
		case "standard":
			map.mapType = .standard
			break
		case "hybrid":
			map.mapType = .hybrid
			break
		default:
			map.mapType = .hybrid
		}
	}
}

private extension MapView {

	func showNodePositions(to view: MKMapView) {
		
		//clear any existing annotations
		if !view.annotations.isEmpty {
			view.removeAnnotations(view.annotations)
		}
		
		for node in self.nodes {
			//try and get the last position
			if (node.positions?.count ?? 0) > 0 && (node.positions!.lastObject as! PositionEntity).coordinate != nil {
				let annotation = PositionAnnotation()
				annotation.coordinate = (node.positions!.lastObject as! PositionEntity).coordinate!
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
