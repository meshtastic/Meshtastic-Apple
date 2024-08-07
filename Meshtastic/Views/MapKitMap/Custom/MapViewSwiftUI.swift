//
//  MapViewSwitUI.swift
//  Meshtastic
//
//  Copyright(c) Josh Pirihi & Garth Vander Houwen 1/16/22.

import Foundation
import SwiftUI
import MapKit
import OSLog

struct PolygonInfo: Codable {
	let stroke: String?
	let strokeWidth, strokeOpacity: Int?
	let fill: String?
	let fillOpacity: Double?
	let title, subtitle: String?
}

func degreesToRadians(_ number: Double) -> Double {
	return number * .pi / 180
}
var currentMapLayer: MapLayer?

struct MapViewSwiftUI: UIViewRepresentable {
	var onLongPress: (_ waypointCoordinate: CLLocationCoordinate2D) -> Void
	var onWaypointEdit: (_ waypointId: Int ) -> Void
	let mapView = MKMapView()
	// Parameters
	let selectedMapLayer: MapLayer
	let selectedWeatherLayer: MapOverlayServer = UserDefaults.mapOverlayServer
	let positions: [PositionEntity]
	let waypoints: [WaypointEntity]
	let userTrackingMode: MKUserTrackingMode
	let showNodeHistory: Bool
	let showRouteLines: Bool
	let mapViewType: MKMapType = MKMapType.standard
	// Offline Map Tiles
	@AppStorage("lastUpdatedLocalMapFile") private var lastUpdatedLocalMapFile = 0
	@State private var loadedLastUpdatedLocalMapFile = 0
	var customMapOverlay: CustomMapOverlay?
	@State private var presentCustomMapOverlayHash: CustomMapOverlay?
	// MARK: Private methods
	private func configureMap(mapView: MKMapView) {
		// Map View Parameters
		mapView.mapType = mapViewType
		mapView.addAnnotations(waypoints)
		// Do the initial map centering
		let latest = positions
			.filter { $0.latest == true }
			.sorted { $0.nodePosition?.num ?? 0 > $1.nodePosition?.num ?? -1 }
		let span =  MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
		let center = (latest.count > 0 && userTrackingMode == MKUserTrackingMode.none) ? latest[0].coordinate : LocationHelper.currentLocation
		let region = MKCoordinateRegion(center: center, span: span)
		mapView.addAnnotations(showNodeHistory ? positions : latest)
		mapView.setRegion(region, animated: true)
		// Set user (phone gps) tracking options
		mapView.setUserTrackingMode(userTrackingMode, animated: true)
		if userTrackingMode == MKUserTrackingMode.none {
			if latest.count == 1 {
				mapView.fit(annotations: showNodeHistory ? positions: latest, andShow: false)
			} else {
				mapView.fitAllAnnotations()
			}
			mapView.showsUserLocation = false
		} else {
			mapView.showsUserLocation = true
		}
		// Other MKMapView Settings
		mapView.preferredConfiguration.elevationStyle = .realistic// .flat
		mapView.pointOfInterestFilter = MKPointOfInterestFilter.excludingAll
		mapView.isPitchEnabled = true
		mapView.isRotateEnabled = true
		mapView.isScrollEnabled = true
		mapView.isZoomEnabled = true
		mapView.showsBuildings = true
		mapView.showsScale = true
		mapView.showsTraffic = true

		mapView.showsCompass = false
		let compass = MKCompassButton(mapView: mapView)
		compass.translatesAutoresizingMaskIntoConstraints = false
		#if targetEnvironment(macCatalyst)
		// Show the default always visible compass and the mac only controls
		compass.compassVisibility = .visible
		mapView.addSubview(compass)
		mapView.showsZoomControls = true
		mapView.showsPitchControl = true
		compass.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -115).isActive = true
		compass.bottomAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -5).isActive = true
		#else
		compass.compassVisibility = .adaptive
		mapView.addSubview(compass)
		compass.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -5).isActive = true
		compass.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 145).isActive = true
		#endif
	}
	private func setMapBaseLayer(mapView: MKMapView) {
		// Avoid refreshing UI if selectedLayer has not changed
		guard currentMapLayer != selectedMapLayer else { return }
		currentMapLayer = selectedMapLayer
		for overlay in mapView.overlays where overlay is MKTileOverlay {
			mapView.removeOverlay(overlay)
		}
		switch selectedMapLayer {
		case .offline:
			mapView.mapType = .standard
			let overlay = TileOverlay()
			overlay.canReplaceMapContent = false
			overlay.minimumZ = UserDefaults.mapTileServer.zoomRange.startIndex
			overlay.maximumZ = UserDefaults.mapTileServer.zoomRange.endIndex
			mapView.addOverlay(overlay, level: UserDefaults.mapTilesAboveLabels ? .aboveLabels : .aboveRoads)
		case .satellite:
			mapView.mapType = .satellite
		case .hybrid:
			mapView.mapType = .hybrid
		default:
			mapView.mapType = .standard
		}
	}
	private func setMapOverlays(mapView: MKMapView) {
		// Weather radar
		if UserDefaults.enableOverlayServer {
			let locale = Locale.current
			if locale.region?.identifier ?? "no locale" == "US" {
				let overlay = MKTileOverlay(urlTemplate: selectedWeatherLayer.tileUrl)
				overlay.canReplaceMapContent = false
				overlay.minimumZ = selectedWeatherLayer.zoomRange.startIndex
				overlay.maximumZ = selectedWeatherLayer.zoomRange.endIndex
				mapView.addOverlay(overlay, level: .aboveLabels)
			}
		}
	}

	func makeUIView(context: Context) -> MKMapView {
		currentMapLayer = nil
		mapView.delegate = context.coordinator
		self.configureMap(mapView: mapView)
		return mapView
	}
	func updateUIView(_ mapView: MKMapView, context: Context) {
		// Set selected map base layer
		setMapBaseLayer(mapView: mapView)
		// Set map tile server and weather overlay layers
		setMapOverlays(mapView: mapView)
		let latest = positions
			.filter { $0.latest == true }
			.sorted { $0.nodePosition?.num ?? 0 > $1.nodePosition?.num ?? -1 }
		// Node Route Lines
		if showRouteLines {
			// Remove all existing PolyLine Overlays
			for overlay in mapView.overlays where overlay is MKPolyline {
				mapView.removeOverlay(overlay)
			}
			var lineIndex = 0
			for position in latest {
				let nodePositions = positions.filter { $0.nodeCoordinate != nil && $0.nodePosition?.num ?? 0 == position.nodePosition?.num ?? -1 }
				let lineCoords = nodePositions.compactMap({(position) -> CLLocationCoordinate2D in
					return position.nodeCoordinate ?? LocationHelper.DefaultLocation
				})
				let polyline = MKPolyline(coordinates: lineCoords, count: nodePositions.count)
				polyline.title = "\(String(position.nodePosition?.num ?? 0))"
				mapView.addOverlay(polyline, level: .aboveLabels)
				lineIndex += 1
				// There are 18 colors for lines, start over if we are at index 17
				if lineIndex > 17 {
					lineIndex = 0
				}
			}
		} else {
			// Remove all existing PolyLine Overlays
			for overlay in mapView.overlays where overlay is MKPolyline {
				mapView.removeOverlay(overlay)
			}
		}
		let annotationCount = waypoints.count + (showNodeHistory ? positions.count : latest.count)
		if annotationCount != mapView.annotations.count {
			Logger.services.info("Annotation Count: \(annotationCount) Map Annotations: \(mapView.annotations.count)")
			mapView.removeAnnotations(mapView.annotations)
			mapView.addAnnotations(waypoints)
		}
		mapView.addAnnotations(showNodeHistory ? positions : latest)
		if userTrackingMode == MKUserTrackingMode.none {
			mapView.showsUserLocation = false
			if UserDefaults.enableMapRecentering {
				if latest.count == 1 {
					mapView.fit(annotations: showNodeHistory ? positions : latest, andShow: true)
				} else {
					mapView.fitAllAnnotations()
				}
			}
		} else {
			mapView.showsUserLocation = true
		}
		mapView.setUserTrackingMode(userTrackingMode, animated: true)
	}
	func makeCoordinator() -> MapCoordinator {
		return Coordinator(self)
	}
	final class MapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
		var parent: MapViewSwiftUI
		var longPressRecognizer = UILongPressGestureRecognizer()
		init(_ parent: MapViewSwiftUI) {
			self.parent = parent
			super.init()
			self.longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressHandler))
			self.longPressRecognizer.minimumPressDuration = 0.5
			self.longPressRecognizer.cancelsTouchesInView = true
			self.longPressRecognizer.delegate = self
			self.parent.mapView.addGestureRecognizer(longPressRecognizer)
		}
		func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
			switch annotation {
			case let positionAnnotation as PositionEntity:
				let reuseID = String(positionAnnotation.nodePosition?.num ?? 0) + "-" + String(positionAnnotation.time?.timeIntervalSince1970 ?? 0)
				let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "node") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseID )
				annotationView.tag = -1
				annotationView.canShowCallout = true
				if positionAnnotation.latest {
					annotationView.markerTintColor = UIColor(hex: UInt32(positionAnnotation.nodePosition?.num ?? 0)).darker()
					annotationView.displayPriority = .required
					annotationView.titleVisibility = .visible
				} else {
					annotationView.markerTintColor = UIColor(hex: UInt32(positionAnnotation.nodePosition?.num ?? 0)).lighter()
					annotationView.displayPriority = .defaultHigh
					annotationView.titleVisibility = .adaptive
				}
				annotationView.tag = -1
				annotationView.canShowCallout = true
				annotationView.titleVisibility = .adaptive
				let leftIcon = UIImageView(image: annotationView.glyphText?.image())
				leftIcon.backgroundColor = UIColor(.indigo)
				annotationView.leftCalloutAccessoryView = leftIcon
				let subtitle = UILabel()
				subtitle.text = "Long Name: \(positionAnnotation.nodePosition?.user?.longName ?? "Unknown") \n"
				subtitle.text? += "Latitude: \(String(format: "%.5f", positionAnnotation.coordinate.latitude)) \n"
				subtitle.text! += "Longitude: \(String(format: "%.5f", positionAnnotation.coordinate.longitude)) \n"
				let distanceFormatter = MKDistanceFormatter()
				subtitle.text! += "Altitude: \(distanceFormatter.string(fromDistance: Double(positionAnnotation.altitude))) \n"
				if positionAnnotation.nodePosition?.metadata != nil {
					if DeviceRoles(rawValue: Int(positionAnnotation.nodePosition!.metadata?.role ?? 0)) == DeviceRoles.client ||
						DeviceRoles(rawValue: Int(positionAnnotation.nodePosition!.metadata?.role ?? 0)) == DeviceRoles.clientMute ||
						DeviceRoles(rawValue: Int(positionAnnotation.nodePosition!.metadata?.role ?? 0)) == DeviceRoles.routerClient {
						annotationView.glyphImage = UIImage(systemName: "flipphone")
					} else if DeviceRoles(rawValue: Int(positionAnnotation.nodePosition!.metadata?.role ?? 0)) == DeviceRoles.repeater {
						annotationView.glyphImage = UIImage(systemName: "repeat")
					} else if DeviceRoles(rawValue: Int(positionAnnotation.nodePosition!.metadata?.role ?? 0)) == DeviceRoles.router {
						annotationView.glyphImage = UIImage(systemName: "wifi.router.fill")
					} else if DeviceRoles(rawValue: Int(positionAnnotation.nodePosition!.metadata?.role ?? 0)) == DeviceRoles.tracker {
						annotationView.glyphImage = UIImage(systemName: "location.viewfinder")
					} else if DeviceRoles(rawValue: Int(positionAnnotation.nodePosition!.metadata?.role ?? 0)) == DeviceRoles.sensor {
						annotationView.glyphImage = UIImage(systemName: "sensor")
					}
					let pf = PositionFlags(rawValue: Int(positionAnnotation.nodePosition?.metadata?.positionFlags ?? 3))
					if pf.contains(.Satsinview) {
						subtitle.text! += "Sats in view: \(String(positionAnnotation.satsInView)) \n"
					}
					if pf.contains(.SeqNo) {
						subtitle.text! += "Sequence: \(String(positionAnnotation.seqNo)) \n"
					}
					if pf.contains(.Heading) {
						if parent.userTrackingMode != MKUserTrackingMode.followWithHeading {
							annotationView.glyphImage = UIImage(systemName: "location.north.fill")?.rotate(radians: Float(degreesToRadians(Double(positionAnnotation.heading))))
							subtitle.text! += "Heading: \(String(positionAnnotation.heading)) \n"
						} else {
							annotationView.glyphImage = UIImage(systemName: "flipphone")
						}
					}
					if pf.contains(.Speed) {
						let formatter = MeasurementFormatter()
						formatter.locale = Locale.current
						if positionAnnotation.speed <= 1 {
							annotationView.glyphImage = UIImage(systemName: "hexagon")
						}
						subtitle.text! += "Speed: \(formatter.string(from: Measurement(value: Double(positionAnnotation.speed), unit: UnitSpeed.kilometersPerHour))) \n"
					}
				} else {
					// node metadata is nil
					annotationView.glyphImage = UIImage(systemName: "flipphone")
				}
				if LocationHelper.currentLocation.distance(from: LocationHelper.DefaultLocation) > 0.0 {
					let metersAway = positionAnnotation.coordinate.distance(from: LocationHelper.currentLocation)
					subtitle.text! += "distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway))) \n"
				}
				subtitle.text! += positionAnnotation.time?.formatted() ?? "Unknown \n"
				subtitle.numberOfLines = 0
				annotationView.detailCalloutAccessoryView = subtitle
				let detailsIcon = UIButton(type: .detailDisclosure)
				detailsIcon.setImage(UIImage(systemName: "trash"), for: .normal)
				annotationView.rightCalloutAccessoryView = detailsIcon
				return annotationView
			case let waypointAnnotation as WaypointEntity:
				let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "waypoint") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: String(waypointAnnotation.id))
				annotationView.tag = Int(waypointAnnotation.id)
				annotationView.isEnabled = true
				annotationView.canShowCallout = true
				if waypointAnnotation.icon == 0 {
					annotationView.glyphText = "📍"
				} else {
					annotationView.glyphText = String(UnicodeScalar(Int(waypointAnnotation.icon)) ?? "📍")
				}
				annotationView.markerTintColor = UIColor(.accentColor)
				annotationView.displayPriority = .required
				annotationView.titleVisibility = .adaptive
				let leftIcon = UIImageView(image: annotationView.glyphText?.image())
				leftIcon.backgroundColor = UIColor(.accentColor)
				annotationView.leftCalloutAccessoryView = leftIcon
				let subtitle = UILabel()
				if waypointAnnotation.longDescription?.count ?? 0 > 0 {
					subtitle.text = (waypointAnnotation.longDescription ?? "") + "\n"
				} else {
					subtitle.text = ""
				}
				if LocationHelper.currentLocation.distance(from: LocationHelper.DefaultLocation) > 0.0 {
					let metersAway = waypointAnnotation.coordinate.distance(from: LocationHelper.currentLocation)
					let distanceFormatter = MKDistanceFormatter()
					subtitle.text! += "distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway))) \n"
				}
				if waypointAnnotation.created != nil {
					subtitle.text! += "Created: \(waypointAnnotation.created?.formatted() ?? "Unknown") \n"
				}
				if waypointAnnotation.lastUpdated != nil {
					subtitle.text! += "Updated: \(waypointAnnotation.lastUpdated?.formatted() ?? "Unknown") \n"
				}
				if waypointAnnotation.expire != nil {
					subtitle.text! += "Expires: \(waypointAnnotation.expire?.formatted() ?? "Unknown") \n"
				}
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
			switch view.annotation {
			case _ as WaypointEntity:
				// Only Allow Edit for waypoint annotations with a id
				if view.tag > 0 {
					parent.onWaypointEdit(view.tag)
				}
			default: break
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
			if let tileOverlay = overlay as? MKTileOverlay {
				return MKTileOverlayRenderer(tileOverlay: tileOverlay)
			} else {
				if let routePolyline = overlay as? MKPolyline {
					let titleString = routePolyline.title ?? "0"
					let renderer = MKPolylineRenderer(polyline: routePolyline)
					renderer.strokeColor = UIColor(hex: UInt32(titleString) ?? 0).lighter()
					renderer.lineWidth = 8
					return renderer
				}
				if let polygon = overlay as? MKPolygon {
					let renderer = MKPolygonRenderer(polygon: polygon)
					renderer.fillColor = UIColor.purple.withAlphaComponent(0.2)
					renderer.strokeColor = .purple.withAlphaComponent(0.7)
					return renderer
				}
				return MKOverlayRenderer(overlay: overlay)
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
			if mapName == nil || mapName! == "" {
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
}
