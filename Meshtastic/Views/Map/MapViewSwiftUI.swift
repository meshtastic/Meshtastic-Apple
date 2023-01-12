//
//  MapViewSwitUI.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 1/9/23.
//

import SwiftUI
import MapKit

struct MapViewSwiftUI: UIViewRepresentable {
	
	let mapView = MKMapView()
	let positions: [PositionEntity]
	let region: MKCoordinateRegion
	let mapViewType: MKMapType
	
	func makeUIView(context: Context) -> MKMapView {
		mapView.mapType = mapViewType
		mapView.setRegion(region, animated: true)
		mapView.isRotateEnabled = true
		mapView.isPitchEnabled = true
		mapView.showsBuildings = true;
		mapView.addAnnotations(positions)
		mapView.showsUserLocation = true
		mapView.setUserTrackingMode(.followWithHeading, animated: true)
		mapView.showsCompass = true
		mapView.showsScale = true
		mapView.isScrollEnabled = true
		mapView.delegate = context.coordinator
		return mapView
	}
	
	func updateUIView(_ mapView: MKMapView, context: Context) {
		mapView.mapType = mapViewType
	}
	
	func makeCoordinator() -> MapCoordinator {
		return Coordinator(self)
	}
	
	final class MapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
		
		var parent: MapViewSwiftUI
		var gRecognizer = UITapGestureRecognizer()
		
		init(_ parent: MapViewSwiftUI) {
			self.parent = parent
			super.init()
			self.gRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapHandler))
			self.gRecognizer.delegate = self
			self.parent.mapView.addGestureRecognizer(gRecognizer)
		}
		
		func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
			
			switch annotation {
				
			case _ as MKClusterAnnotation:
				let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "nodeGroup") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "nodeGroup")
				annotationView.markerTintColor = .systemRed
				return annotationView
			case _ as PositionEntity:
				let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "node") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "Node")
				annotationView.canShowCallout = true
				annotationView.glyphText = "📟"
				annotationView.clusteringIdentifier = "nodeGroup"
				annotationView.markerTintColor = UIColor(.accentColor)
				annotationView.titleVisibility = .visible
				return annotationView
			default: return nil
			}
		}
		
		@objc func tapHandler(_ gesture: UITapGestureRecognizer) {
			// Screen Position - CGPoint
			let location = gRecognizer.location(in: self.parent.mapView)
			// Map Coordinate - CLLocationCoordinate2D
			let coordinate = self.parent.mapView.convert(location, toCoordinateFrom: self.parent.mapView)
			print(coordinate)
		}
	}
}
