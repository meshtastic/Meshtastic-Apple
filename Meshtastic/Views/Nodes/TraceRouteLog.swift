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
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@ObservedObject var node: NodeInfoEntity
	@State private var selectedRoute: TraceRouteEntity?

	var body: some View {
		VStack {
			VStack {
				List(node.traceRoutes?.reversed() as? [TraceRouteEntity] ?? [], id: \.self, selection: $selectedRoute) { route in
					Text("\(route.time?.formatted() ?? "unknown".localized) - \(route.response ? (route.hops?.count == 0 && route.response ? "Direct" : "Other") : "No Response")")
				}
				.listStyle(.plain)
			}
			.navigationTitle("Trace Route List")
			VStack {
				if selectedRoute != nil {
					Divider()
					if selectedRoute?.response ?? false && selectedRoute?.hops?.count ?? 0 > 0 {
						Text("Trace Route received by \(selectedRoute?.node?.user?.longName ?? "unknown".localized)")
						Text("Route: \(selectedRoute?.routeText ?? "unknown".localized)")
							.font(.title)
					} else if selectedRoute?.response ?? false {
						Text("Trace Route received directly by \(selectedRoute?.node?.user?.longName ?? "unknown".localized)")
							.font(.title)
					}
					let hopsArray = selectedRoute?.hops?.array as? [TraceRouteHopEntity] ?? []
					let lineCoords = hopsArray.compactMap({(hop) -> CLLocationCoordinate2D in
						return hop.coordinate ?? LocationHelper.DefaultLocation
					})
					if selectedRoute?.response ?? false  {
						Map() {
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
								if selectedRoute?.node?.positions?.count ?? 0 > 0 {
									let mostRecent = selectedRoute?.node?.positions?.lastObject as! PositionEntity
									var traceRouteCoords: [CLLocationCoordinate2D] = [selectedRoute?.coordinate ?? LocationsHandler.DefaultLocation, mostRecent.coordinate]
									Annotation(selectedRoute?.node?.user?.shortName ?? "???", coordinate: mostRecent.nodeCoordinate ?? LocationHelper.DefaultLocation) {
										ZStack {
											Circle()
												.fill(Color(.black))
												.strokeBorder(.white, lineWidth: 3)
												.frame(width: 15, height: 15)
										}
									}
									let dashed = StrokeStyle(
										lineWidth: 3,
										lineCap: .round, lineJoin: .round, dash: [7, 10]
									)
									MapPolyline(coordinates: traceRouteCoords)
										.stroke(.blue, style: dashed)
								}
							}
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
					} else {
						Text("Trace Route sent to \(selectedRoute?.node?.user?.longName ?? "unknown".localized)")
							.font(.title)
							.padding(.top)
						Spacer()
						Text("\(selectedRoute?.time?.formatted() ?? "")")
							.font(.title3)
						Spacer()
						Text("No response")
							.font(.title2)
						Spacer()
					}
				}
			}
			.navigationTitle("Route Details")
		}
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
		}
	}
}
