////
////  MapView.swift
////  MapViewTest
////
////  Created by Cem Yilmaz on 05.07.21.
////
//import SwiftUI
//import MapKit
//import CoreData
//
//#if canImport(MapKit) && canImport(UIKit)
//public struct MapView: UIViewRepresentable {
//
//	@Environment(\.managedObjectContext) var context
//	
//	//var context: NSManagedObjectContext?
//	
//	//@Binding private var region: MKCoordinateRegion
//	
//	//make this view dependent on the UserDefault that is updated when importing a new map file
//	@AppStorage("lastUpdatedLocalMapFile") private var lastUpdatedLocalMapFile = 0
//	@State private var loadedLastUpdatedLocalMapFile = 0
//	
//	private var customMapOverlay: CustomMapOverlay?
//	@State private var presentCustomMapOverlayHash: CustomMapOverlay?
//	
//	private var mapType: MKMapType
//	
//	private var showZoomScale: Bool
//	private var zoomEnabled: Bool
//	private var zoomRange: (minHeight: CLLocationDistance?, maxHeight: CLLocationDistance?)
//	
//	private var scrollEnabled: Bool
//	private var scrollBoundaries: MKCoordinateRegion?
//	
//	private var rotationEnabled: Bool
//	private var showCompassWhenRotated: Bool
//	
//	private var showUserLocation: Bool
//	private var userTrackingMode: MKUserTrackingMode
//	@Binding private var userLocation: CLLocationCoordinate2D?
//	
//	private var overlays: [Overlay]
//	
//	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "time", ascending: false)], animation: .default)
//	private var positions: FetchedResults<PositionEntity>
//	
//	public init(
//		customMapOverlay: CustomMapOverlay? = nil,
//		mapType: String = "hybrid",
//		zoomEnabled: Bool = true,
//		showZoomScale: Bool = false,
//		zoomRange: (minHeight: CLLocationDistance?, maxHeight: CLLocationDistance?) = (nil, nil),
//		scrollEnabled: Bool = true,
//		scrollBoundaries: MKCoordinateRegion? = nil,
//		rotationEnabled: Bool = true,
//		showCompassWhenRotated: Bool = true,
//		showUserLocation: Bool = true,
//		userTrackingMode: MKUserTrackingMode = MKUserTrackingMode.none,
//		userLocation: Binding<CLLocationCoordinate2D?> = .constant(nil),
//		overlays: [Overlay] = []
//	) {
//		self.customMapOverlay = customMapOverlay
//		
//		switch mapType {
//		case "satellite":
//			self.mapType = .satellite
//			break
//		case "standard":
//			self.mapType = .standard
//			break
//		case "hybrid":
//			self.mapType = .hybrid
//			break
//		default:
//			self.mapType = .hybrid
//		}
//		
//		self.showZoomScale = showZoomScale
//		self.zoomEnabled = zoomEnabled
//		self.zoomRange = zoomRange
//		
//		self.scrollEnabled = scrollEnabled
//		self.scrollBoundaries = scrollBoundaries
//		
//		self.rotationEnabled = rotationEnabled
//		self.showCompassWhenRotated = showCompassWhenRotated
//		
//		self.showUserLocation = showUserLocation
//		self.userTrackingMode = userTrackingMode
//		self._userLocation = userLocation
//		
//		self.overlays = overlays
//		
//	}
//	
//	public func makeUIView(context: Context) -> MKMapView {
//		let mapView = MKMapView()
//		mapView.delegate = context.coordinator
//		mapView.register(PositionAnnotationView.self, forAnnotationViewWithReuseIdentifier: NSStringFromClass(PositionAnnotationView.self))
//		
//		return mapView
//	}
//	
//	
//	public func updateUIView(_ mapView: MKMapView, context: Context) {
//		
//		if self.customMapOverlay != self.presentCustomMapOverlayHash || self.loadedLastUpdatedLocalMapFile != self.lastUpdatedLocalMapFile {
//			mapView.removeOverlays(mapView.overlays)
//			if let customMapOverlay = self.customMapOverlay {
//				
//				let fileManager = FileManager.default
//				let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
//				let tilePath = documentsDirectory.appendingPathComponent("offline_map.mbtiles", isDirectory: false).path
//				if fileManager.fileExists(atPath: tilePath) {
//				//if let tilePath = Bundle.main.path(forResource: "offline_map", ofType: "mbtiles") {
//					
//					print("Loading local map file")
//					
//					if let overlay = LocalMBTileOverlay(mbTilePath: tilePath) {
//					
//						overlay.canReplaceMapContent = false//customMapOverlay.canReplaceMapContent
//					
//						mapView.addOverlay(overlay)
//					}
//				} else {
//					print("Couldn't find a local map file to load")
//				}
//			}
//			DispatchQueue.main.async {
//				self.presentCustomMapOverlayHash = self.customMapOverlay
//				self.loadedLastUpdatedLocalMapFile = self.lastUpdatedLocalMapFile
//			}
//		}
//		
//		if mapView.mapType != self.mapType {
//			mapView.mapType = self.mapType
//		}
//		
//		mapView.showsScale = self.zoomEnabled ? self.showZoomScale : false
//		
//		if mapView.isZoomEnabled != self.zoomEnabled {
//			mapView.isZoomEnabled = self.zoomEnabled
//		}
//		
//		if mapView.cameraZoomRange.minCenterCoordinateDistance != self.zoomRange.minHeight ?? 0 ||
//			mapView.cameraZoomRange.maxCenterCoordinateDistance != self.zoomRange.maxHeight ?? .infinity {
//			mapView.cameraZoomRange = MKMapView.CameraZoomRange(
//				minCenterCoordinateDistance: self.zoomRange.minHeight ?? 0,
//				maxCenterCoordinateDistance: self.zoomRange.maxHeight ?? .infinity
//			)
//		}
//		
//		mapView.isScrollEnabled = self.userTrackingMode == MKUserTrackingMode.none ? self.scrollEnabled : false
//		
//		if let scrollBoundary = self.scrollBoundaries, (mapView.cameraBoundary?.region.center.latitude != scrollBoundary.center.latitude || mapView.cameraBoundary?.region.center.longitude != scrollBoundary.center.longitude || mapView.camera Boundary?.region.span.latitudeDelta != scrollBoundary.span.latitudeDelta || mapView.cameraBoundary?.region.span.longitudeDelta != scrollBoundary.span.longitudeDelta) {
//			mapView.cameraBoundary = MKMapView.CameraBoundary(coordinateRegion: scrollBoundary)
//		} else if self.scrollBoundaries == nil && mapView.cameraBoundary != nil {
//			mapView.cameraBoundary = nil
//		}
//		
//		mapView.isRotateEnabled = self.userTrackingMode != .followWithHeading ? self.rotationEnabled : false
//		mapView.showsCompass = self.userTrackingMode != .followWithHeading ? self.showCompassWhenRotated : false
//		
//		if mapView.showsUserLocation != self.showUserLocation {
//			mapView.showsUserLocation = self.showUserLocation
//		}
//		
//		if mapView.userTrackingMode != self.userTrackingMode {
//			mapView.userTrackingMode = self.userTrackingMode
//		}
//		
//		// clear any existing annotations
//		var shouldMoveRegion = false
//		if !mapView.annotations.isEmpty {
//			mapView.removeAnnotations(mapView.annotations)
//		} else {
//			shouldMoveRegion = true
//		}
//		
//		var displayedNodes: [Int64] = []
//		for position in self.positions {
//			if position.nodePosition == nil || displayedNodes.contains(position.nodePosition!.num) || position.coordinate == nil {
//				continue
//			}
//			
//			let annotation = PositionAnnotation()
//			annotation.coordinate = position.nodeCoordinate!
//			annotation.title = position.nodePosition!.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown")
//			annotation.shortName = position.nodePosition!.user?.shortName?.uppercased() ?? "???"
//
//			mapView.addAnnotation(annotation)
//			
//			displayedNodes.append(position.nodePosition!.num)
//		}
//		
//		if shouldMoveRegion {
//			self.moveToMeshRegion(mapView)
//		}
//		
//		
//	}
//	
//	func moveToMeshRegion(_ mapView: MKMapView) {
//		//go through the annotations and create a bounding box that encloses them
//		
//		var minLat: CLLocationDegrees = 90.0
//		var maxLat: CLLocationDegrees = -90.0
//		var minLon: CLLocationDegrees = 180.0
//		var maxLon: CLLocationDegrees = -180.0
//		
//		for annotation in mapView.annotations {
//			if annotation.isKind(of: PositionAnnotation.self) {
//				minLat = min(minLat, annotation.coordinate.latitude)
//				maxLat = max(maxLat, annotation.coordinate.latitude)
//				minLon = min(minLon, annotation.coordinate.longitude)
//				maxLon = max(maxLon, annotation.coordinate.longitude)
//			}
//		}
//		
//		//check if the mesh region looks sensible before we move to it.  Otherwise we won't move the map (leave it at the current location)
//		if maxLat < minLat || (maxLat-minLat) > 5 || maxLon < minLon || (maxLon-minLon) > 5 {
//			return
//		} else if minLat == maxLat && minLon == maxLon {
//			//then we are focussed on a single point (probably because there is only one node with a position)
//			//widen that out a little (don't zoom way in to that point)
//			
//			//0.001 degrees latitude is about 100m
//			//the mapView.regionThatFits call below will expand this out to a rectangle
//			minLat = minLat - 0.001
//			maxLat = maxLat + 0.001
//		}
//		
//		let centerCoord = CLLocationCoordinate2D(latitude: (minLat+maxLat)/2, longitude: (minLon+maxLon)/2)
//		
//		let span = MKCoordinateSpan(latitudeDelta: (maxLat-minLat)*1.5, longitudeDelta: (maxLon-minLon)*1.5)
//		
//		let region = mapView.regionThatFits(MKCoordinateRegion(center: centerCoord, span: span))
//		
//		mapView.setRegion(region, animated: true)
//	}
//	
//	public func makeCoordinator() -> Coordinator {
//		Coordinator(parent: self)
//	}
//	
//	public class Coordinator: NSObject, MKMapViewDelegate {
//			
//		private var parent: MapView
//		public var overlays: [Overlay] = []
//		
//		init(parent: MapView) {
//			self.parent = parent
//		}
//		
//		public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
//
//			guard !annotation.isKind(of: MKUserLocation.self) else {
//				// Make a fast exit if the annotation is the `MKUserLocation`, as it's not an annotation view we wish to customize.
//				return nil
//			}
//
//			if let annotation = annotation as? PositionAnnotation {
//
//				let annotationView = PositionAnnotationView(annotation: annotation, reuseIdentifier: "PositionAnnotation")
//				annotationView.name = annotation.shortName ?? "????"
//				annotationView.canShowCallout = true
//				
//				return annotationView
//			}
//
//			return nil
//		}
//		
//		public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
//
//			if let index = self.overlays.firstIndex(where: { overlay_ in overlay_.shape.hash == overlay.hash }) {
//
//				let unwrappedOverlay = self.overlays[index]
//
//				if let circleOverlay = unwrappedOverlay.shape as? MKCircle {
//
//					let renderer = MKCircleRenderer(circle: circleOverlay)
//					renderer.fillColor = unwrappedOverlay.fillColor
//					renderer.strokeColor = unwrappedOverlay.strokeColor
//					renderer.lineWidth = unwrappedOverlay.lineWidth
//					return renderer
//
//				} else if let polygonOverlay = unwrappedOverlay.shape as? MKPolygon {
//
//					let renderer = MKPolygonRenderer(polygon: polygonOverlay)
//					renderer.fillColor = unwrappedOverlay.fillColor
//					renderer.strokeColor = unwrappedOverlay.strokeColor
//					renderer.lineWidth = unwrappedOverlay.lineWidth
//					return renderer
//
//				} else if let multiPolygonOverlay = unwrappedOverlay.shape as? MKMultiPolygon {
//
//					let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygonOverlay)
//					renderer.fillColor = unwrappedOverlay.fillColor
//					renderer.strokeColor = unwrappedOverlay.strokeColor
//					renderer.lineWidth = unwrappedOverlay.lineWidth
//					return renderer
//
//				} else if let polyLineOverlay = unwrappedOverlay.shape as? MKPolyline {
//
//					let renderer = MKPolylineRenderer(polyline: polyLineOverlay)
//					renderer.fillColor = unwrappedOverlay.fillColor
//					renderer.strokeColor = unwrappedOverlay.strokeColor
//					renderer.lineWidth = unwrappedOverlay.lineWidth
//					return renderer
//
//				} else if let multiPolylineOverlay = unwrappedOverlay.shape as? MKMultiPolyline {
//
//					let renderer = MKMultiPolylineRenderer(multiPolyline: multiPolylineOverlay)
//					renderer.fillColor = unwrappedOverlay.fillColor
//					renderer.strokeColor = unwrappedOverlay.strokeColor
//					renderer.lineWidth = unwrappedOverlay.lineWidth
//					return renderer
//
//				} else {
//
//					return MKOverlayRenderer()
//
//				}
//
//			} else if let tileOverlay = overlay as? MKTileOverlay {
//
//				return MKTileOverlayRenderer(tileOverlay: tileOverlay)
//
//			} else {
//				return MKOverlayRenderer()
//			}
//		}
//	}
//
//	/// is supposed to be located in the folder with the map name
//	public struct DefaultTile: Hashable {
//		let tileName: String
//		let tileType: String
//
//		public init(tileName: String, tileType: String) {
//			self.tileName = tileName
//			self.tileType = tileType
//		}
//	}
//
//	public struct CustomMapOverlay: Equatable, Hashable {
//		let mapName: String
//		let tileType: String
//		var canReplaceMapContent: Bool
//		var minimumZoomLevel: Int?
//		var maximumZoomLevel: Int?
//		let defaultTile: DefaultTile?
//
//		public init(
//			mapName: String,
//			tileType: String,
//			canReplaceMapContent: Bool = true, // false for transparent tiles
//			minimumZoomLevel: Int? = nil,
//			maximumZoomLevel: Int? = nil,
//			defaultTile: DefaultTile? = nil
//		) {
//			
//			self.mapName = mapName
//			self.tileType = tileType
//			self.canReplaceMapContent = canReplaceMapContent
//			self.minimumZoomLevel = minimumZoomLevel
//			self.maximumZoomLevel = maximumZoomLevel
//			self.defaultTile = defaultTile
//		}
//		
//		public init?(
//			mapName: String?,
//			tileType: String,
//			canReplaceMapContent: Bool = true, // false for transparent tiles
//			minimumZoomLevel: Int? = nil,
//			maximumZoomLevel: Int? = nil,
//			defaultTile: DefaultTile? = nil
//		) {
//			if (mapName == nil || mapName! == "") {
//				return nil
//			}
//			self.mapName = mapName!
//			self.tileType = tileType
//			self.canReplaceMapContent = canReplaceMapContent
//			self.minimumZoomLevel = minimumZoomLevel
//			self.maximumZoomLevel = maximumZoomLevel
//			self.defaultTile = defaultTile
//		}
//	}
//
//	public class CustomMapOverlaySource: MKTileOverlay {
//
//		// requires folder: tiles/{mapName}/z/y/y,{tileType}
//		private var parent: MapView
//		private let mapName: String
//		private let tileType: String
//		private let defaultTile: DefaultTile?
//
//		public init(
//			parent: MapView,
//			mapName: String,
//			tileType: String,
//			defaultTile: DefaultTile?
//		) {
//			self.parent = parent
//			self.mapName = mapName
//			self.tileType = tileType
//			self.defaultTile = defaultTile
//			super.init(urlTemplate: "")
//		}
//
//		public override func url(forTilePath path: MKTileOverlayPath) -> URL {
//			if let tileUrl = Bundle.main.url(
//				forResource: "\(path.y)",
//				withExtension: self.tileType,
//				subdirectory: "tiles/\(self.mapName)/\(path.z)/\(path.x)",
//				localization: nil
//			) {
//				return tileUrl
//			} else if let defaultTile = self.defaultTile, let defaultTileUrl = Bundle.main.url(
//				forResource: defaultTile.tileName,
//				withExtension: defaultTile.tileType,
//				subdirectory: "tiles/\(self.mapName)",
//				localization: nil
//			) {
//				return defaultTileUrl
//			} else {
//				let urlstring = self.mapName+"\(path.z)/\(path.x)/\(path.y).png"
//				return URL(string: urlstring)!
//				// Bundle.main.url(forResource: "surrounding", withExtension: "png", subdirectory: "tiles")!
//			}
//		
//		}
//		
//	}
//	
//	public struct Overlay {
//		
//		public static func == (lhs: MapView.Overlay, rhs: MapView.Overlay) -> Bool {
//			// maybe to use in the future for comparison of full array
//			lhs.shape.coordinate.latitude == rhs.shape.coordinate.latitude &&
//			lhs.shape.coordinate.longitude == rhs.shape.coordinate.longitude &&
//			lhs.fillColor == rhs.fillColor
//		}
//
//		var shape: MKOverlay
//		var fillColor: UIColor?
//		var strokeColor: UIColor?
//		var lineWidth: CGFloat
//
//		public init(
//			shape: MKOverlay,
//			fillColor: UIColor? = nil,
//			strokeColor: UIColor? = nil,
//			lineWidth: CGFloat = 0
//		) {
//			self.shape = shape
//			self.fillColor = fillColor
//			self.strokeColor = strokeColor
//			self.lineWidth = lineWidth
//		}
//	}
//	
//}
//
//// MARK: End of implementation
//#endif
