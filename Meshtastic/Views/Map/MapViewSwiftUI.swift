//
//  MapViewSwitUI.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 1/9/23.
//

import SwiftUI
import MapKit

struct MapViewSwiftUI: UIViewRepresentable {
	
	var onMarkerTap: (_ waypointCoordinate: CLLocationCoordinate2D? ) -> Void
	let mapView = MKMapView()
	let positions: [PositionEntity]
	let region: MKCoordinateRegion
	let mapViewType: MKMapType
	
	
	// Offline Maps
	//make this view dependent on the UserDefault that is updated when importing a new map file
	@AppStorage("lastUpdatedLocalMapFile") private var lastUpdatedLocalMapFile = 0
	@State private var loadedLastUpdatedLocalMapFile = 0
	var customMapOverlay: CustomMapOverlay?
	@State private var presentCustomMapOverlayHash: CustomMapOverlay?
	var overlays: [Overlay] = []
	
	func makeUIView(context: Context) -> MKMapView {
		mapView.mapType = mapViewType
		mapView.setRegion(region, animated: true)
		mapView.isRotateEnabled = true
		mapView.isPitchEnabled = true
		mapView.showsBuildings = true;
		mapView.addAnnotations(positions)
		mapView.showsUserLocation = true
		mapView.setUserTrackingMode(.none, animated: false)
		mapView.showsCompass = true
		mapView.showsScale = true
		mapView.isZoomEnabled = true
		mapView.isScrollEnabled = true
		mapView.delegate = context.coordinator
		return mapView
	}
	
	func updateUIView(_ mapView: MKMapView, context: Context) {
		mapView.mapType = mapViewType
		
		if self.customMapOverlay != self.presentCustomMapOverlayHash || self.loadedLastUpdatedLocalMapFile != self.lastUpdatedLocalMapFile {
			mapView.removeOverlays(mapView.overlays)
			if self.customMapOverlay != nil {
				
				let fileManager = FileManager.default
				let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
				let tilePath = documentsDirectory.appendingPathComponent("offline_map.mbtiles", isDirectory: false).path
				if fileManager.fileExists(atPath: tilePath) {
				//if let tilePath = Bundle.main.path(forResource: "offline_map", ofType: "mbtiles") {
					
					print("Loading local map file")
					
					if let overlay = LocalMBTileOverlay(mbTilePath: tilePath) {
					
						overlay.canReplaceMapContent = false//customMapOverlay.canReplaceMapContent
					
						mapView.addOverlay(overlay)
					}
				} else {
					print("Couldn't find a local map file to load")
				}
			}
			DispatchQueue.main.async {
				self.presentCustomMapOverlayHash = self.customMapOverlay
				self.loadedLastUpdatedLocalMapFile = self.lastUpdatedLocalMapFile
			}
		}
	}
	
	func makeCoordinator() -> MapCoordinator {
		return Coordinator(self)
	}
	
	final class MapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
		
		var parent: MapViewSwiftUI
		var longPressRecognizer = UILongPressGestureRecognizer()
		
		var overlays: [Overlay] = []
		
		init(_ parent: MapViewSwiftUI) {
			self.parent = parent
			super.init()
			self.longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressHandler))
			self.longPressRecognizer.minimumPressDuration = 0.2
			self.longPressRecognizer.delegate = self
			self.parent.mapView.addGestureRecognizer(longPressRecognizer)
			self.overlays = []
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
			case _ as WaypointEntity:
				return nil
				
			default: return nil
			}
		}
		
		@objc func longPressHandler(_ gesture: UILongPressGestureRecognizer) {
			// Screen Position - CGPoint
			let location = longPressRecognizer.location(in: self.parent.mapView)
			// Map Coordinate - CLLocationCoordinate2D
			let coordinate = self.parent.mapView.convert(location, toCoordinateFrom: self.parent.mapView)
			print(coordinate)
			
			// Add annotation:
			let annotation = MKPointAnnotation()
			annotation.title = "Dropped Pin"
			annotation.coordinate = coordinate
			parent.mapView.addAnnotation(annotation)
			parent.onMarkerTap(coordinate)
			UINotificationFeedbackGenerator().notificationOccurred(.success)
		}
		
		public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {

			if let index = self.overlays.firstIndex(where: { overlay_ in overlay_.shape.hash == overlay.hash }) {

				let unwrappedOverlay = self.overlays[index]
				if let circleOverlay = unwrappedOverlay.shape as? MKCircle {
					let renderer = MKCircleRenderer(circle: circleOverlay)
					renderer.fillColor = unwrappedOverlay.fillColor
					renderer.strokeColor = unwrappedOverlay.strokeColor
					renderer.lineWidth = unwrappedOverlay.lineWidth
					return renderer
				} else if let polygonOverlay = unwrappedOverlay.shape as? MKPolygon {
					let renderer = MKPolygonRenderer(polygon: polygonOverlay)
					renderer.fillColor = unwrappedOverlay.fillColor
					renderer.strokeColor = unwrappedOverlay.strokeColor
					renderer.lineWidth = unwrappedOverlay.lineWidth
					return renderer
				} else if let multiPolygonOverlay = unwrappedOverlay.shape as? MKMultiPolygon {
					let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygonOverlay)
					renderer.fillColor = unwrappedOverlay.fillColor
					renderer.strokeColor = unwrappedOverlay.strokeColor
					renderer.lineWidth = unwrappedOverlay.lineWidth
					return renderer
				} else if let polyLineOverlay = unwrappedOverlay.shape as? MKPolyline {
					let renderer = MKPolylineRenderer(polyline: polyLineOverlay)
					renderer.fillColor = unwrappedOverlay.fillColor
					renderer.strokeColor = unwrappedOverlay.strokeColor
					renderer.lineWidth = unwrappedOverlay.lineWidth
					return renderer
				} else if let multiPolylineOverlay = unwrappedOverlay.shape as? MKMultiPolyline {
					let renderer = MKMultiPolylineRenderer(multiPolyline: multiPolylineOverlay)
					renderer.fillColor = unwrappedOverlay.fillColor
					renderer.strokeColor = unwrappedOverlay.strokeColor
					renderer.lineWidth = unwrappedOverlay.lineWidth
					return renderer
				} else {
					return MKOverlayRenderer()
				}

			} else if let tileOverlay = overlay as? MKTileOverlay {
				return MKTileOverlayRenderer(tileOverlay: tileOverlay)
			} else {
				return MKOverlayRenderer()
			}
		}
	}
	
	/// is supposed to be located in the folder with the map name
	public struct DefaultTile: Hashable {
		let tileName: String
		let tileType: String
		
		public init(tileName: String, tileType: String) {
			self.tileName = tileName
			self.tileType = tileType
		}
	}
	
	public struct CustomMapOverlay: Equatable, Hashable {
		let mapName: String
		let tileType: String
		var canReplaceMapContent: Bool
		var minimumZoomLevel: Int?
		var maximumZoomLevel: Int?
		let defaultTile: DefaultTile?
		
		public init(
			mapName: String,
			tileType: String,
			canReplaceMapContent: Bool = true, // false for transparent tiles
			minimumZoomLevel: Int? = nil,
			maximumZoomLevel: Int? = nil,
			defaultTile: DefaultTile? = nil
		) {
			
			self.mapName = mapName
			self.tileType = tileType
			self.canReplaceMapContent = canReplaceMapContent
			self.minimumZoomLevel = minimumZoomLevel
			self.maximumZoomLevel = maximumZoomLevel
			self.defaultTile = defaultTile
		}
		
		public init?(
			mapName: String?,
			tileType: String,
			canReplaceMapContent: Bool = true, // false for transparent tiles
			minimumZoomLevel: Int? = nil,
			maximumZoomLevel: Int? = nil,
			defaultTile: DefaultTile? = nil
		) {
			if (mapName == nil || mapName! == "") {
				return nil
			}
			self.mapName = mapName!
			self.tileType = tileType
			self.canReplaceMapContent = canReplaceMapContent
			self.minimumZoomLevel = minimumZoomLevel
			self.maximumZoomLevel = maximumZoomLevel
			self.defaultTile = defaultTile
		}
	}
	
	public class CustomMapOverlaySource: MKTileOverlay {
		
		// requires folder: tiles/{mapName}/z/y/y,{tileType}
		private var parent: MapView
		private let mapName: String
		private let tileType: String
		private let defaultTile: DefaultTile?
		
		public init(
			parent: MapView,
			mapName: String,
			tileType: String,
			defaultTile: DefaultTile?
		) {
			self.parent = parent
			self.mapName = mapName
			self.tileType = tileType
			self.defaultTile = defaultTile
			super.init(urlTemplate: "")
		}
		
		public override func url(forTilePath path: MKTileOverlayPath) -> URL {
			if let tileUrl = Bundle.main.url(
				forResource: "\(path.y)",
				withExtension: self.tileType,
				subdirectory: "tiles/\(self.mapName)/\(path.z)/\(path.x)",
				localization: nil
			) {
				return tileUrl
			} else if let defaultTile = self.defaultTile, let defaultTileUrl = Bundle.main.url(
				forResource: defaultTile.tileName,
				withExtension: defaultTile.tileType,
				subdirectory: "tiles/\(self.mapName)",
				localization: nil
			) {
				return defaultTileUrl
			} else {
				let urlstring = self.mapName+"\(path.z)/\(path.x)/\(path.y).png"
				return URL(string: urlstring)!
			}
			
		}
	}
	
	public struct Overlay {
		
		public static func == (lhs: MapViewSwiftUI.Overlay, rhs: MapViewSwiftUI.Overlay) -> Bool {
			// maybe to use in the future for comparison of full array
			lhs.shape.coordinate.latitude == rhs.shape.coordinate.latitude &&
			lhs.shape.coordinate.longitude == rhs.shape.coordinate.longitude &&
			lhs.fillColor == rhs.fillColor
		}
		
		var shape: MKOverlay
		var fillColor: UIColor?
		var strokeColor: UIColor?
		var lineWidth: CGFloat
		
		public init(
			shape: MKOverlay,
			fillColor: UIColor? = nil,
			strokeColor: UIColor? = nil,
			lineWidth: CGFloat = 0
		) {
			self.shape = shape
			self.fillColor = fillColor
			self.strokeColor = strokeColor
			self.lineWidth = lineWidth
		}
	}
}
