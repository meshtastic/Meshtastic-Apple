//
//  MapViewSwitUI.swift
//  Meshtastic
//
//  Copyright(c) Josh Pirihi & Garth Vander Houwen 1/16/22.

import SwiftUI
import MapKit

struct MapViewSwiftUI: UIViewRepresentable {
	
	var onLongPress: (_ waypointCoordinate: CLLocationCoordinate2D) -> Void
	var onWaypointEdit: (_ waypointId: Int ) -> Void
	let mapView = MKMapView()
	let positions: [PositionEntity]
	let waypoints: [WaypointEntity]
	let mapViewType: MKMapType
	let centerOnPositionsOnly: Bool
	
	// Offline Maps
	//make this view dependent on the UserDefault that is updated when importing a new map file
	@AppStorage("lastUpdatedLocalMapFile") private var lastUpdatedLocalMapFile = 0
	@State private var loadedLastUpdatedLocalMapFile = 0
	var customMapOverlay: CustomMapOverlay?
	@State private var presentCustomMapOverlayHash: CustomMapOverlay?
	var overlays: [Overlay] = []
	let dynamicRegion: Bool = true
	
	func makeUIView(context: Context) -> MKMapView {
		// Parameters
		mapView.addAnnotations(waypoints)
		if centerOnPositionsOnly {
			mapView.fit(annotations: positions, andShow: true)
		} else {
			mapView.addAnnotations(positions)
			mapView.fitAllAnnotations()
		}
		mapView.mapType = mapViewType
		mapView.setUserTrackingMode(.none, animated: true)
		// Other MKMapView Settings
		mapView.isPitchEnabled = true
		mapView.isRotateEnabled = true
		mapView.isScrollEnabled = true
		mapView.isZoomEnabled = true
		mapView.showsBuildings = true
		mapView.showsCompass = true
		mapView.showsScale = true
		mapView.showsTraffic = true
		mapView.showsUserLocation = true
		#if targetEnvironment(macCatalyst)
		mapView.showsZoomControls = true
		#endif
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
		mapView.removeAnnotations(mapView.annotations)
		mapView.addAnnotations(positions)
		mapView.addAnnotations(waypoints)
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
			self.longPressRecognizer.minimumPressDuration = 0.5
			//self.longPressRecognizer.numberOfTouchesRequired = 1
			self.longPressRecognizer.cancelsTouchesInView = true
			self.longPressRecognizer.delegate = self
			self.parent.mapView.addGestureRecognizer(longPressRecognizer)
			self.overlays = []
		}
		
		func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
			
			switch annotation {
				
			case _ as MKClusterAnnotation:
				let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "nodeGroup") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "nodeGroup")
				annotationView.markerTintColor = .brown//.systemRed
				annotationView.displayPriority = .defaultLow
				annotationView.tag = -1
				return annotationView
			case let positionAnnotation as PositionEntity:
				let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "node") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "Node")
				annotationView.tag = -1
				annotationView.canShowCallout = true
				annotationView.glyphText = "📟"
				annotationView.clusteringIdentifier = "nodeGroup"
				annotationView.markerTintColor = UIColor(.indigo)
				annotationView.titleVisibility = .adaptive
				let leftIcon = UIImageView(image: annotationView.glyphText?.image())
				leftIcon.backgroundColor = UIColor(.indigo)
				annotationView.leftCalloutAccessoryView = leftIcon
				let subtitle = UILabel()
				subtitle.text = "Latitude: \(String(format: "%.5f", positionAnnotation.coordinate.latitude)) \n"
				subtitle.text! += "Longitude: \(String(format: "%.5f", positionAnnotation.coordinate.longitude)) \n"
				let distanceFormatter = MKDistanceFormatter()
				subtitle.text! += "Altitude: \(distanceFormatter.string(fromDistance: Double(positionAnnotation.altitude))) \n"
				if positionAnnotation.nodePosition?.metadata != nil {
					let pf = PositionFlags(rawValue: Int(positionAnnotation.nodePosition?.metadata?.positionFlags ?? 3))
					
					if pf.contains(.Satsinview) {
						subtitle.text! += "Sats in view: \(String(positionAnnotation.satsInView)) \n"
					} else if pf.contains(.Speed) {
						let formatter = MeasurementFormatter()
						formatter.locale = Locale.current
						subtitle.text! += "Speed: \(formatter.string(from: Measurement(value: Double(positionAnnotation.speed), unit: UnitSpeed.kilometersPerHour))) \n"
					}
				}
				subtitle.text! += positionAnnotation.time?.formatted() ?? "Unknown \n"
				subtitle.numberOfLines = 0
				annotationView.detailCalloutAccessoryView = subtitle
				//let detailsIcon = UIButton(type: .detailDisclosure)
				//detailsIcon.setImage(UIImage(systemName: "info.square"), for: .normal)
				//annotationView.rightCalloutAccessoryView = detailsIcon
				return annotationView
			case let waypointAnnotation as WaypointEntity:
				let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "waypoint") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "Waypoint")
				annotationView.tag = Int(waypointAnnotation.id)
				annotationView.isEnabled = true
				annotationView.canShowCallout = true
				if waypointAnnotation.icon == 0 {
					annotationView.glyphText = "📍"
				} else {
					annotationView.glyphText = String(UnicodeScalar(Int(waypointAnnotation.icon)) ?? "📍")
				}
				annotationView.clusteringIdentifier = "waypointGroup"
				annotationView.markerTintColor = UIColor(.accentColor)
				annotationView.displayPriority = .required
				annotationView.titleVisibility = .adaptive
				let leftIcon = UIImageView(image: annotationView.glyphText?.image())
				leftIcon.backgroundColor = UIColor(.accentColor)
				annotationView.leftCalloutAccessoryView = leftIcon
				let subtitle = UILabel()
				subtitle.text = waypointAnnotation.longDescription
				subtitle.numberOfLines = 0
				annotationView.detailCalloutAccessoryView = subtitle
				let editIcon = UIButton(type: .detailDisclosure)
				editIcon.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
				annotationView.rightCalloutAccessoryView = editIcon
				return annotationView
			default: return nil
			}
		}
		
		func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
			// Only Allow Edit for waypoint annotations with a id
			if view.tag > 0 {
				parent.onWaypointEdit(view.tag)
			}
		}
		
		@objc func longPressHandler(_ gesture: UILongPressGestureRecognizer) {
			
			if gesture.state != UIGestureRecognizer.State.ended {
				return
			} else if gesture.state != UIGestureRecognizer.State.began {
				
				// Screen Position - CGPoint
				let location = longPressRecognizer.location(in: self.parent.mapView)
				
				// Map Coordinate - CLLocationCoordinate2D
				let coordinate = self.parent.mapView.convert(location, toCoordinateFrom: self.parent.mapView)
				let annotation = MKPointAnnotation()
				annotation.title = "Dropped Pin"
				annotation.coordinate = coordinate
				parent.mapView.addAnnotation(annotation)
				UINotificationFeedbackGenerator().notificationOccurred(.success)
				parent.onLongPress(coordinate)
			}
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
		private var parent: MapViewSwiftUI
		private let mapName: String
		private let tileType: String
		private let defaultTile: DefaultTile?
		
		public init(
			parent: MapViewSwiftUI,
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
