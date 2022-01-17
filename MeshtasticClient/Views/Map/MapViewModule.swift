//
//  MapView.swift
//  MapViewTest
//
//  Created by Cem Yilmaz on 05.07.21.
//
import SwiftUI
import MapKit
import CoreData

#if canImport(MapKit) && canImport(UIKit)
public struct MapView: UIViewRepresentable {

	//@Environment(\.managedObjectContext) var context
	
	var context: NSManagedObjectContext?
	
	//@Binding private var region: MKCoordinateRegion
	
	private var customMapOverlay: CustomMapOverlay?
	@State private var presentCustomMapOverlayHash: CustomMapOverlay?
	
	private var mapType: MKMapType
	
	private var showZoomScale: Bool
	private var zoomEnabled: Bool
	private var zoomRange: (minHeight: CLLocationDistance?, maxHeight: CLLocationDistance?)
	
	private var scrollEnabled: Bool
	private var scrollBoundaries: MKCoordinateRegion?
	
	private var rotationEnabled: Bool
	private var showCompassWhenRotated: Bool
	
	private var showUserLocation: Bool
	private var userTrackingMode: MKUserTrackingMode
	@Binding private var userLocation: CLLocationCoordinate2D?
	
	//private var annotations: [MKPointAnnotation]
	
	private var overlays: [Overlay]
	
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "lastHeard", ascending: false)], animation: .default)
		private var locationNodes: FetchedResults<NodeInfoEntity>
	
	//@State private var locationNodes: [NodeInfoEntity]
	
	public init(
		//region: Binding<MKCoordinateRegion> = .constant(MKCoordinateRegion()),
		customMapOverlay: CustomMapOverlay? = nil,
		//mapType: MKMapType = MKMapType.standard,
		mapType: String = "hybrid",
		zoomEnabled: Bool = true,
		showZoomScale: Bool = false,
		zoomRange: (minHeight: CLLocationDistance?, maxHeight: CLLocationDistance?) = (nil, nil),
		scrollEnabled: Bool = true,
		scrollBoundaries: MKCoordinateRegion? = nil,
		rotationEnabled: Bool = true,
		showCompassWhenRotated: Bool = true,
		showUserLocation: Bool = true,
		userTrackingMode: MKUserTrackingMode = MKUserTrackingMode.none,
		userLocation: Binding<CLLocationCoordinate2D?> = .constant(nil),
		//annotations: [MKPointAnnotation] = [],
		//locationNodes: [NodeInfoEntity] = [],
		overlays: [Overlay] = [],
		context: NSManagedObjectContext? = nil
	) {
		//self._region = region
		
		self.customMapOverlay = customMapOverlay
		
		switch mapType {
		case "satellite":
			self.mapType = .satellite
			break
		case "standard":
			self.mapType = .standard
			break
		case "hybrid":
			self.mapType = .hybrid
			break
		default:
			self.mapType = .hybrid
		}
		//self.mapType = mapType
		
		self.showZoomScale = showZoomScale
		self.zoomEnabled = zoomEnabled
		self.zoomRange = zoomRange
		
		self.scrollEnabled = scrollEnabled
		self.scrollBoundaries = scrollBoundaries
		
		self.rotationEnabled = rotationEnabled
		self.showCompassWhenRotated = showCompassWhenRotated
		
		self.showUserLocation = showUserLocation
		self.userTrackingMode = userTrackingMode
		self._userLocation = userLocation
		
		//self.annotations = annotations
		
		//self.locationNodes = locationNodes
		
		self.overlays = overlays
		
	}
	
	public func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator
		mapView.register(PositionAnnotationView.self, forAnnotationViewWithReuseIdentifier: NSStringFromClass(PositionAnnotationView.self))
		
		Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { timer in
			for node in self.locationNodes {
				// try and get the last position
				if (node.positions?.count ?? 0) > 0 && (node.positions!.lastObject as! PositionEntity).coordinate != nil {
					let annotation = PositionAnnotation()
					annotation.coordinate = (node.positions!.lastObject as! PositionEntity).coordinate!
					annotation.title = node.user?.longName ?? "Unknown"
					annotation.shortName = node.user?.shortName?.uppercased() ?? "???"

					mapView.addAnnotation(annotation)
				}
			}
		}
		
		return mapView
	}
	
	
	public func updateUIView(_ mapView: MKMapView, context: Context) {
		
		//if self.userTrackingMode == MKUserTrackingMode.none && (mapView.region.center.latitude != self.region.center.latitude || mapView.region.center.longitude != self.region.center.longitude) {
			//mapView.region = self.region
		//}
		
		if self.customMapOverlay != self.presentCustomMapOverlayHash {
			mapView.removeOverlays(mapView.overlays)
			if let customMapOverlay = self.customMapOverlay {
				let overlay = CustomMapOverlaySource(
					parent: self,
					mapName: customMapOverlay.mapName,
					tileType: customMapOverlay.tileType,
					defaultTile: customMapOverlay.defaultTile
				)
				
				if let minZ = customMapOverlay.minimumZoomLevel {
					overlay.minimumZ = minZ
				}
				
				if let maxZ = customMapOverlay.maximumZoomLevel {
					overlay.maximumZ = maxZ
				}
				
				overlay.canReplaceMapContent = customMapOverlay.canReplaceMapContent
				
				mapView.addOverlay(overlay)
			}
			DispatchQueue.main.async {
				self.presentCustomMapOverlayHash = self.customMapOverlay
			}
		}
		
		if mapView.overlays.count != (self.overlays.count + (self.customMapOverlay == nil ? 0 : 1)) {
			context.coordinator.overlays = self.overlays
			mapView.overlays.forEach { overlay in
				if !(overlay is MKTileOverlay) {
					mapView.removeOverlay(overlay)
				}
			}
			mapView.addOverlays(self.overlays.map { overlay in overlay.shape })
		}
		
		if mapView.mapType != self.mapType {
			mapView.mapType = self.mapType
		}
		
		mapView.showsScale = self.zoomEnabled ? self.showZoomScale : false
		
		if mapView.isZoomEnabled != self.zoomEnabled {
			mapView.isZoomEnabled = self.zoomEnabled
		}
		
		if mapView.cameraZoomRange.minCenterCoordinateDistance != self.zoomRange.minHeight ?? 0 ||
			mapView.cameraZoomRange.maxCenterCoordinateDistance != self.zoomRange.maxHeight ?? .infinity {
			mapView.cameraZoomRange = MKMapView.CameraZoomRange(
				minCenterCoordinateDistance: self.zoomRange.minHeight ?? 0,
				maxCenterCoordinateDistance: self.zoomRange.maxHeight ?? .infinity
			)
		}
		
		mapView.isScrollEnabled = self.userTrackingMode == MKUserTrackingMode.none ? self.scrollEnabled : false
		
		if let scrollBoundary = self.scrollBoundaries, (mapView.cameraBoundary?.region.center.latitude != scrollBoundary.center.latitude || mapView.cameraBoundary?.region.center.longitude != scrollBoundary.center.longitude || mapView.cameraBoundary?.region.span.latitudeDelta != scrollBoundary.span.latitudeDelta || mapView.cameraBoundary?.region.span.longitudeDelta != scrollBoundary.span.longitudeDelta) {
			mapView.cameraBoundary = MKMapView.CameraBoundary(coordinateRegion: scrollBoundary)
		} else if self.scrollBoundaries == nil && mapView.cameraBoundary != nil {
			mapView.cameraBoundary = nil
		}
		
		mapView.isRotateEnabled = self.userTrackingMode != .followWithHeading ? self.rotationEnabled : false
		mapView.showsCompass = self.userTrackingMode != .followWithHeading ? self.showCompassWhenRotated : false
		
		if mapView.showsUserLocation != self.showUserLocation {
			mapView.showsUserLocation = self.showUserLocation
		}
		
		if mapView.userTrackingMode != self.userTrackingMode {
			mapView.userTrackingMode = self.userTrackingMode
		}
		
		//if mapView.annotations.filter({ annotation in !(annotation is MKUserLocation) }).count != self.annotations.count {
		//	mapView.removeAnnotations(mapView.annotations)
		//	mapView.addAnnotations(self.annotations)
		//}
		
		// clear any existing annotations
		var shouldMoveRegion = false
		if !mapView.annotations.isEmpty {
			mapView.removeAnnotations(mapView.annotations)
		} else {
			shouldMoveRegion = true
		}

		for node in self.locationNodes {
			// try and get the last position
			if (node.positions?.count ?? 0) > 0 && (node.positions!.lastObject as! PositionEntity).coordinate != nil {
				let annotation = PositionAnnotation()
				annotation.coordinate = (node.positions!.lastObject as! PositionEntity).coordinate!
				annotation.title = node.user?.longName ?? "Unknown"
				annotation.shortName = node.user?.shortName?.uppercased() ?? "???"

				mapView.addAnnotation(annotation)
			}
		}
		
		if shouldMoveRegion {
			self.moveToMeshRegion(mapView)
		}
		
		
	}
	
	func moveToMeshRegion(_ mapView: MKMapView) {
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
		
		//check if the mesh region looks sensible before we move to it.  Otherwise we won't move the map (leave it at the current location)
		if maxLat < minLat || (maxLat-minLat) > 5 || maxLon < minLon || (maxLon-minLon) > 5 {
			return
		}
		
		let centerCoord = CLLocationCoordinate2D(latitude: (minLat+maxLat)/2, longitude: (minLon+maxLon)/2)
		
		let span = MKCoordinateSpan(latitudeDelta: (maxLat-minLat)*1.5, longitudeDelta: (maxLon-minLon)*1.5)
		
		let region = mapView.regionThatFits(MKCoordinateRegion(center: centerCoord, span: span))
		
		mapView.setRegion(region, animated: true)
		
		
	}
	
	public func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}
	
	public class Coordinator: NSObject, MKMapViewDelegate {
			
		private var parent: MapView
		public var overlays: [Overlay] = []
		
		init(parent: MapView) {
			self.parent = parent
		}
		
		/*public func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
			DispatchQueue.main.async {
				self.parent.region = mapView.region
			}
		}*/
		
		public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {

			guard !annotation.isKind(of: MKUserLocation.self) else {
				// Make a fast exit if the annotation is the `MKUserLocation`, as it's not an annotation view we wish to customize.
				return nil
			}

			var annotationView: MKAnnotationView?

			if let annotation = annotation as? PositionAnnotation {
				let identifier = NSStringFromClass(PositionAnnotationView.self)

				//let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? PositionAnnotationView ?? PositionAnnotationView()
				let annotationView = PositionAnnotationView(annotation: annotation, reuseIdentifier: "PositionAnnotation")

				annotationView.name = annotation.shortName ?? "???"

				annotationView.canShowCallout = true
				
				return annotationView
			}

			return annotationView
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
				// Bundle.main.url(forResource: "surrounding", withExtension: "png", subdirectory: "tiles")!
			}
		
		}
		
	}
	
	public struct Overlay {
		
		public static func == (lhs: MapView.Overlay, rhs: MapView.Overlay) -> Bool {
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

// MARK: End of implementation
// MARK: Demonstration
/*
public struct MapViewDemo: View {

	@State private var locationManager: CLLocationManager

	@State private var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
		center: CLLocationCoordinate2D(
			latitude: -38.758247,
			longitude: 175.360208
		),
		span: MKCoordinateSpan(
			latitudeDelta: 0.01,
			longitudeDelta: 0.01
		)
	)

	@State private var customMapOverlay: MapView.CustomMapOverlay?

	@State private var mapType: MKMapType = MKMapType.standard

	@State private var zoomEnabled: Bool = true
	@State private var showZoomScale: Bool = true
	@State private var useMinZoomBoundary: Bool = false
	@State private var minZoom: Double = 0
	@State private var useMaxZoomBoundary: Bool = false
	@State private var maxZoom: Double = 3000000

	@State private var scrollEnabled: Bool = true
	@State private var useScrollBoundaries: Bool = false
	@State private var scrollBoundaries: MKCoordinateRegion = MKCoordinateRegion()

	@State private var rotationEnabled: Bool = true
	@State private var showCompassWhenRotated: Bool = true

	@State private var showUserLocation: Bool = true
	@State private var userTrackingMode: MKUserTrackingMode = MKUserTrackingMode.none
	@State private var userLocation: CLLocationCoordinate2D?

	@State private var showAnnotations: Bool = true
	@State private var annotations: [MKPointAnnotation] = []

	@State private var showOverlays: Bool = true
	@State private var overlays: [MapView.Overlay] = []

	@State private var showMapCenter: Bool = false

	public init() {
		self.locationManager = CLLocationManager()
		self.locationManager.requestWhenInUseAuthorization()
	}

	public var body: some View {

		NavigationView {
			
			List {

				Section(header: Text("Scroll")) {
					Toggle("Scroll enabled", isOn: self.$scrollEnabled)
					Toggle("Use scroll boundaries", isOn: self.$useScrollBoundaries)
						.onChange(of: self.useScrollBoundaries) { newValue in
							if newValue {
								self.scrollBoundaries = MKCoordinateRegion(center: self.mapRegion.center, span: MKCoordinateSpan())
							}
						}
					if self.useScrollBoundaries {
						VStack(alignment: .leading) {
							Text(String(format: "Vertical distance to center: %.2f m", self.scrollBoundaries.span.latitudeDelta * 10609))
							Slider(value: self.$scrollBoundaries.span.latitudeDelta, in: 0...(300/10609))
						}
						VStack(alignment: .leading) {
							Text(String(format: "Horizontal distance to center: %.2f m", self.self.scrollBoundaries.span.longitudeDelta * 10609))
							Slider(value: self.$scrollBoundaries.span.longitudeDelta, in: 0...(300/10609))
						}
					}
				}
				
				Section(header: Text("Zoom")) {
					Toggle("Zoom enabled", isOn: self.$zoomEnabled)
					Toggle("Show zoom scale", isOn: self.$showZoomScale)
					Toggle("Use minimum zoom boundary", isOn: self.$useMinZoomBoundary)
					if self.useMinZoomBoundary {
						VStack(alignment: .leading) {
							Text(String(format: "Minimum Height: %.2f m", self.minZoom))
							Slider(value: self.$minZoom, in: 0...(self.useMaxZoomBoundary ? self.maxZoom : 3000000), step: 10)
						}
					}
					Toggle("Use maximum zoom boundary", isOn: self.$useMaxZoomBoundary)
					if self.useMaxZoomBoundary {
						VStack(alignment: .leading) {
							Text(String(format: "Maximum Height: %.2f m", self.maxZoom))
							Slider(value: self.$maxZoom, in: (self.useMinZoomBoundary ? self.minZoom : 0)...3000000, step: 10)
						}
					}
				}
				
				Section(header: Text("Rotation")) {
					Toggle("Rotation enabled", isOn: self.$rotationEnabled)
					Toggle("Show compass when rotated", isOn: self.$showCompassWhenRotated)
				}
				
				Section {
					Toggle("Show map Center", isOn: self.$showMapCenter)
				}
				
				Section(header: Text("User Location")) {
					Toggle("Show User Location", isOn: self.$showUserLocation)
					Picker("Follow Mode", selection: self.$userTrackingMode) {
						Text("Nicht folgen").tag(MKUserTrackingMode.none)
						Text("Folgen").tag(MKUserTrackingMode.follow)
						Text("Richtung folgen").tag(MKUserTrackingMode.followWithHeading)
					}.pickerStyle(MenuPickerStyle())
					
				}
				
				Section(header: Text("Annotations")) {
					Toggle("Show Annotations", isOn: self.$showAnnotations)
					Button("Add Annotation") {
						let annotation = MKPointAnnotation()
						annotation.coordinate = self.mapRegion.center
						annotation.title = "Title"
						annotation.subtitle = "Subtitle"
						self.annotations.append(annotation)
					}

					Button("Delete all") { self.annotations = [] }.foregroundColor(.red)
				}
				
				Section(header: Text("Overlays")) {
					Toggle("Show Overlays", isOn: self.$showOverlays)
					Button("Add circle") {
						self.overlays.append(MapView.Overlay(
							shape: MKCircle(
								center: self.mapRegion.center,
								radius: 20
							),
							strokeColor: UIColor.systemBlue,
							lineWidth: 10
						))
					}
					
					Button("Delete all") { self.overlays = [] }.foregroundColor(.red)
				}
				
				Section(header: Text("Custom Map Overlay")) {
					Button("Keine") { self.customMapOverlay = nil }
					Button("OSM Online") {
						self.customMapOverlay = MapView.CustomMapOverlay(
							mapName: "https://tile.openstreetmap.org/",
							tileType: "png",
							canReplaceMapContent: true
						)
					}
					Button("Farm Map") {
						self.customMapOverlay = MapView.CustomMapOverlay(
							mapName: "http://10.147.253.250:5050/local/map/",
							tileType: "png",
							canReplaceMapContent: true
						)
					}
				}
				
			}.listStyle(GroupedListStyle())
			.navigationBarTitle("Map Configuration", displayMode: NavigationBarItem.TitleDisplayMode.inline)
			
			ZStack {
				
				MapView(
					region: self.$mapRegion,
					customMapOverlay: self.customMapOverlay,
					mapType: self.mapType,
					zoomEnabled: self.zoomEnabled,
					showZoomScale: self.showZoomScale,
					zoomRange: (minHeight: self.useMinZoomBoundary ? self.minZoom : 0, maxHeight: self.useMaxZoomBoundary ? self.maxZoom : .infinity),
					scrollEnabled: self.scrollEnabled,
					scrollBoundaries: self.useScrollBoundaries ? self.scrollBoundaries : nil,
					rotationEnabled: self.rotationEnabled,
					showCompassWhenRotated: self.showCompassWhenRotated,
					showUserLocation: self.showUserLocation,
					userTrackingMode: self.userTrackingMode,
					userLocation: self.$userLocation,
					annotations: self.showAnnotations ? self.annotations : [],
					overlays: self.showOverlays ? self.overlays : []
				)
				
				VStack {
					
					Spacer()
					
					HStack {
						if let userLocation = self.userLocation, self.showUserLocation {
							VStack(alignment: .leading) {
								Button("Center user location") {
									self.mapRegion.center = userLocation
								}
								Text("User Location").bold()
								Text("\(userLocation.latitude)")
								Text("\(userLocation.longitude)")
							}
						}
						
						Spacer()
						
						VStack(alignment: .leading) {
							Text("Map Center").bold()
							Text("\(self.mapRegion.center.latitude)")
							Text("\(self.mapRegion.center.longitude)")
						}
					}
					
					Picker("", selection: self.$mapType) {
						Text("Standard").tag(MKMapType.standard)
						Text("Muted Standard").tag(MKMapType.mutedStandard)
						Text("Satellite").tag(MKMapType.satellite)
						Text("Satellite Flyover").tag(MKMapType.satelliteFlyover)
						Text("Hybrid").tag(MKMapType.hybrid)
						Text("Hybrid Flyover").tag(MKMapType.hybridFlyover)
					}.pickerStyle(SegmentedPickerStyle())
					
					if self.showMapCenter {
						Circle().frame(width: 8, height: 8).foregroundColor(.red)
					}
					
				}.padding()
				
			}.navigationBarTitle("SwiftUI MapView", displayMode: NavigationBarItem.TitleDisplayMode.inline)
			.ignoresSafeArea(edges: .bottom)
			
		}

	}

}


public struct MapView_Previews: PreviewProvider {

	public static var previews: some View {

		MapViewDemo()

	}

}*/
#endif
