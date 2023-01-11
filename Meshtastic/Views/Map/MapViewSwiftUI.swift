//
//  MapViewSwitUI.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 1/9/23.
//

import SwiftUI
import MapKit

struct MapViewSwiftUI: UIViewRepresentable {
	
	let positions: [PositionEntity]
	let region: MKCoordinateRegion
	let mapViewType: MKMapType
	
	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
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
		let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapMap(sender:)))
		mapView.addGestureRecognizer(gestureRecognizer)
		  
		return mapView
	}
	
	func updateUIView(_ mapView: MKMapView, context: Context) {
		mapView.mapType = mapViewType
	}
	
	func makeCoordinator() -> MapCoordinator {
		.init()
	}
	
	final class MapCoordinator: NSObject, MKMapViewDelegate {
				
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
		@objc func tapMap(sender: UITapGestureRecognizer) {
			if sender.state == .ended {
				//let locationInMap = sender.location(in: control.mapView)
				//let coordinateSet = control.mapView.convert(locationInMap, toCoordinateFrom: control.mapView)
			}
		}
	}
}
