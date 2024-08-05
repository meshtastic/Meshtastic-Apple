//
//  TraceRouteLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/7/23.
//

import SwiftUI
#if canImport(MapKit)
import MapKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct TraceRouteLog: View {
	@ObservedObject var locationsHandler = LocationsHandler.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@ObservedObject var node: NodeInfoEntity
	@State private var selectedRoute: TraceRouteEntity?
	// Map Configuration
	@Namespace var mapScope
	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .realistic, emphasis: MapStyle.StandardEmphasis.muted, pointsOfInterest: .all, showsTraffic: true)
	@State var position = MapCameraPosition.automatic
	let distanceFormatter = MKDistanceFormatter()

	var body: some View {
		HStack(alignment: .top) {
			VStack {
				VStack {
					List(node.traceRoutes?.reversed() as? [TraceRouteEntity] ?? [], id: \.self, selection: $selectedRoute) { route in

						Label {
							Text("\(route.time?.formatted() ?? "unknown".localized) - \(route.response ? (route.hops?.count == 0 && route.response ? "Direct" : "\(route.hops?.count ?? 0) \(route.hops?.count ?? 0 == 1 ? "Hop": "Hops")") : "No Response")")
						} icon: {
							Image(systemName: route.response ? (route.hops?.count == 0 && route.response ? "person.line.dotted.person" : "point.3.connected.trianglepath.dotted") : "person.slash")
								.symbolRenderingMode(.hierarchical)
						}
					}
					.listStyle(.plain)
				}
				.frame(minHeight: 200, maxHeight: 230)
				VStack {
					if selectedRoute != nil {
						if selectedRoute?.response ?? false && selectedRoute?.hops?.count ?? 0 > 0 {

							Label {
								Text("Route: \(selectedRoute?.routeText ?? "unknown".localized)")
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title2)
						} else if selectedRoute?.response ?? false {
							Label {
								Text("Trace route received directly by \(selectedRoute?.node?.user?.longName ?? "unknown".localized)")
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title2)
						}
						if selectedRoute?.response ?? false {
							if selectedRoute?.hasPositions ?? false {
								Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
									Annotation("You", coordinate: selectedRoute?.coordinate ?? LocationHelper.DefaultLocation) {
										ZStack {
											Circle()
												.fill(Color(.green))
												.strokeBorder(.white, lineWidth: 3)
												.frame(width: 15, height: 15)
										}
									}
									.annotationTitles(.automatic)
									// Direct Trace Route
									if selectedRoute?.response ?? false && selectedRoute?.hops?.count ?? 0 == 0 {
										if selectedRoute?.node?.positions?.count ?? 0 > 0, let mostRecent = selectedRoute?.node?.positions?.lastObject as? PositionEntity {
											let traceRouteCoords: [CLLocationCoordinate2D] = [selectedRoute?.coordinate ?? LocationsHandler.DefaultLocation, mostRecent.coordinate]
											Annotation(selectedRoute?.node?.user?.shortName ?? "???", coordinate: mostRecent.nodeCoordinate ?? LocationHelper.DefaultLocation) {
												ZStack {
													Circle()
														.fill(Color(.black))
														.strokeBorder(.white, lineWidth: 3)
														.frame(width: 15, height: 15)
												}
											}
											let dashed = StrokeStyle(
												lineWidth: 2,
												lineCap: .round, lineJoin: .round, dash: [7, 10]
											)
											MapPolyline(coordinates: traceRouteCoords)
												.stroke(.blue, style: dashed)
										}
									} else if selectedRoute?.hops?.count ?? 0 == 0 {

									}
								}
								.frame(maxWidth: .infinity, maxHeight: .infinity)
							}
							VStack {
								/// Distance
								if selectedRoute?.node?.positions?.count ?? 0 > 0,
								   selectedRoute?.coordinate != nil,
									let mostRecent = selectedRoute?.node?.positions?.lastObject as? PositionEntity {

									let startPoint = CLLocation(latitude: selectedRoute?.coordinate?.latitude ?? LocationsHandler.DefaultLocation.latitude, longitude: selectedRoute?.coordinate?.longitude ?? LocationsHandler.DefaultLocation.longitude)

									if startPoint.distance(from: CLLocation(latitude: LocationsHandler.DefaultLocation.latitude, longitude: LocationsHandler.DefaultLocation.longitude)) > 0.0 {
										let metersAway = selectedRoute?.coordinate?.distance(from: CLLocationCoordinate2D(latitude: mostRecent.latitude ?? LocationsHandler.DefaultLocation.latitude, longitude: mostRecent.longitude ?? LocationsHandler.DefaultLocation.longitude))
										Label {
											Text("distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway ?? 0)))")
												.foregroundColor(.primary)
										} icon: {
											Image(systemName: "lines.measurement.horizontal")
												.symbolRenderingMode(.hierarchical)
										}
									}
								}
							}
						} else {
							VStack {
								Label {
									Text("Trace route sent to \(selectedRoute?.node?.user?.longName ?? "unknown".localized)")
								} icon: {
									Image(systemName: "signpost.right.and.left")
										.symbolRenderingMode(.hierarchical)
								}
								.font(.title3)
								Spacer()
							}
						}
					} else {
						ContentUnavailableView("Select a Trace Route", systemImage: "signpost.right.and.left")
					}
				}
				Spacer()
			}
			.navigationTitle("Trace Route Log")
		}
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
	}
}
