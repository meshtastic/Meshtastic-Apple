//
//  TraceRouteLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/7/23.
//

import SwiftUI
import SwiftUIBackports
import CoreData
import OSLog
import MapKit

struct TraceRouteLog: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@ObservedObject var locationsHandler = LocationsHandler.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@ObservedObject var node: NodeInfoEntity
	@State private var selectedRoute: TraceRouteEntity?
	// Map Configuration
	@Namespace var mapScope
	let distanceFormatter = MKDistanceFormatter()
	/// State for the circle of routes
	var modemPreset: ModemPresets = ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast
	@State private var indexes: Int = 0
	@State var angle: Angle = .zero
	@State var animation: Animation?

	var body: some View {
		HStack(alignment: .top) {
			VStack {
				VStack {
					List(node.traceRoutes?.reversed() as? [TraceRouteEntity] ?? [], id: \.self, selection: $selectedRoute) { route in
						Label {
							let routeTime = route.time?.formatted() ?? "Unknown".localized
							if route.response && route.hopsTowards == route.hopsBack {
								let hopString = String(localized: "\(route.hopsTowards) Hops")
								Text("\(routeTime) - \(hopString)")
									.font(.caption)
							} else if route.response {
								let hopTowardsString = String(localized: "\(route.hopsTowards) Hops")
								let hopBackString = route.hopsBack >= 0 ? String(localized: "\(route.hopsBack) Hops") : String(localized: "Unknown")
								Text("\(routeTime) - \(hopTowardsString) Towards  \(hopBackString) Back")
									.font(.caption)
							} else if route.sent {
								Text("\(routeTime) - No Response")
									.font(.caption)
							} else {
								Text("\(routeTime) - Not Sent")
									.font(.caption)
							}
						} icon: {
							Image(systemName: route.response ? (route.hopsTowards == 0 && route.response ? "person.line.dotted.person" : "point.3.connected.trianglepath.dotted") : "person.slash")
								.symbolRenderingMode(.hierarchical)
						}
						.swipeActions {
							Button(role: .destructive) {
								context.delete(route)
								do {
									try context.save()
								} catch let error as NSError {
									Logger.data.error("\(error.localizedDescription, privacy: .public)")
								}
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
					.listStyle(.plain)
				}
				Divider()
				ScrollView {
					if selectedRoute != nil {
						if selectedRoute?.response ?? false && selectedRoute?.hopsTowards ?? 0 >= 0 {
							Label {
								Text("Route: \(selectedRoute?.routeText ?? "Unknown".localized)")
							} icon: {
								Image(systemName: "signpost.right")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title3)
							Label {
								Text("Route Back: \(selectedRoute?.routeBackText ?? "Unknown".localized)")
							} icon: {
								Image(systemName: "signpost.left")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title3)
						} else if !(selectedRoute?.sent ?? true) {
								Label {
									VStack {
										Text("Trace route to \(selectedRoute?.node?.user?.longName ?? "Unknown".localized) was not sent.")
											.font(idiom == .phone ? .body : .largeTitle)
											.fontWeight(.semibold)
										Text("Trace Route was rate limited. You can send a trace route a maximum of once every thirty seconds.")
											.font(idiom == .phone ? .caption : .body)
											.foregroundStyle(.secondary)
											.padding()
									}
								} icon: {
									Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
										.symbolRenderingMode(.hierarchical)
								}
						} else {
							   Label {
								   VStack {
									   Text("Trace route sent to \(selectedRoute?.node?.user?.longName ?? "Unknown".localized)")
										   .font(idiom == .phone ? .body : .largeTitle)
										   .fontWeight(.semibold)
									   Text("A Trace Route was sent, no response has been received.")
										   .font(idiom == .phone ? .caption : .body)
										   .foregroundStyle(.secondary)
										   .padding()
								   }
							   } icon: {
								   Image(systemName: "signpost.right.and.left")
									   .symbolRenderingMode(.hierarchical)
							   }
						}
						if false {// selectedRoute?.hops?.count ?? 0 >= 3 {
							HStack(alignment: .center) {
								GeometryReader { geometry in
									let size = ((geometry.size.width >= geometry.size.height ? geometry.size.height : geometry.size.width) / 2) - (idiom == .phone ? 45 : 85)
									Spacer()
									if #available(iOS 16.0, *) {
										TraceRoute(radius: size < 600 ? size : 600, rotation: angle) {
											contents()
										}
										.padding(.leading, idiom == .phone ? 0 : 20)
									} else {
										contents()
										.padding(.leading, idiom == .phone ? 0 : 20)
									}
									Spacer()
								}
								.scaledToFit()
							}
							.onAppear {
								// Set the view rotation animation after the view appeared,
								// to avoid animating initial rotation
								DispatchQueue.main.async {
									indexes = (selectedRoute?.hops?.array.count ?? 0) * 2
									animation = .easeInOut(duration: 1.0)
									withAnimation(.easeInOut(duration: 2.0)) {
										angle = (angle == .degrees(-90) ? .degrees(-90) : .degrees(-90))
									}
								}
							}
							.onTapGesture {
								withAnimation(.easeInOut(duration: 2.0)) {
									angle = (angle == .degrees(-90) ? .degrees(90) : .degrees(-90))
								}
							}
						}
						if selectedRoute?.hasPositions ?? false {
//							Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
//								Annotation("You", coordinate: selectedRoute?.coordinate ?? LocationHelper.DefaultLocation) {
//									ZStack {
//										Circle()
//											.fill(Color(.green))
//											.strokeBorder(.white, lineWidth: 3)
//											.frame(width: 15, height: 15)
//									}
//								}
//								.annotationTitles(.automatic)
//								// Direct Trace Route
//								if selectedRoute?.response ?? false && selectedRoute?.hops?.count ?? 0 == 0 {
//									if selectedRoute?.node?.positions?.count ?? 0 > 0, let mostRecent = selectedRoute?.node?.positions?.lastObject as? PositionEntity {
//										let traceRouteCoords: [CLLocationCoordinate2D] = [selectedRoute?.coordinate ?? LocationsHandler.DefaultLocation, mostRecent.coordinate]
//										Annotation(selectedRoute?.node?.user?.shortName ?? "???", coordinate: mostRecent.nodeCoordinate ?? LocationHelper.DefaultLocation) {
//											ZStack {
//												Circle()
//													.fill(Color(.black))
//													.strokeBorder(.white, lineWidth: 3)
//													.frame(width: 15, height: 15)
//											}
//										}
//										let dashed = StrokeStyle(
//											lineWidth: 2,
//											lineCap: .round, lineJoin: .round, dash: [7, 10]
//										)
//										MapPolyline(coordinates: traceRouteCoords)
//											.stroke(.blue, style: dashed)
//									}
//								}
//							}
//							.frame(maxWidth: .infinity, minHeight: 250)
//							if selectedRoute?.response ?? false {
//								VStack {
//									/// Distance
//									if selectedRoute?.node?.positions?.count ?? 0 > 0,
//									   selectedRoute?.coordinate != nil,
//									   let mostRecent = selectedRoute?.node?.positions?.lastObject as? PositionEntity {
//										let startPoint = CLLocation(latitude: selectedRoute?.coordinate?.latitude ?? LocationsHandler.DefaultLocation.latitude, longitude: selectedRoute?.coordinate?.longitude ?? LocationsHandler.DefaultLocation.longitude)
//										if startPoint.distance(from: CLLocation(latitude: LocationsHandler.DefaultLocation.latitude, longitude: LocationsHandler.DefaultLocation.longitude)) > 0.0 {
//											let metersAway = selectedRoute?.coordinate?.distance(from: CLLocationCoordinate2D(latitude: mostRecent.latitude ?? LocationsHandler.DefaultLocation.latitude, longitude: mostRecent.longitude ?? LocationsHandler.DefaultLocation.longitude))
//											Label {
//												Text("distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway ?? 0)))")
//													.foregroundColor(.primary)
//											} icon: {
//												Image(systemName: "lines.measurement.horizontal")
//													.symbolRenderingMode(.hierarchical)
//											}
//										}
//									}
//								}
//							}
							Spacer()
								.padding(.bottom, 125)
						}
					} else {
						Backport.ContentUnavailableView("Select a Trace Route", systemImage: "signpost.right.and.left")
					}
				}
				.edgesIgnoringSafeArea(.bottom)
			}
			.navigationTitle("Trace Route Log")
		}
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
		})
	}
	@ViewBuilder func contents(animation: Animation? = nil) -> some View {
		ForEach(0..<indexes, id: \.self) { idx in
			if #available(iOS 16.0, *) {
				TraceRouteComponent(animation: animation) {
					routeItem(at: idx)
				}
			} else {
				routeItem(at: idx)
			}
		}
	}

	@ViewBuilder private func routeItem(at idx: Int) -> some View {
		let hops = selectedRoute?.hops?.array as? [TraceRouteHopEntity] ?? []
		if idx % 2 == 0 {
			let i = idx / 2
			let snrColor = getSnrColor(snr: hops[i].snr, preset: modemPreset)
			VStack {
				let nodeColor = UIColor(hex: UInt32(truncatingIfNeeded: hops[i].num))
				CircleText(text: String(hops[i].num.toHex().suffix(4)), color: Color(nodeColor), circleSize: idiom == .phone ? 70 : 125)
					Text("\(String(format: "%.2f", hops[i].snr)) dB")
						.font(idiom == .phone ? .caption2.weight(.semibold) : .headline.weight(.semibold))
						.foregroundColor(snrColor)
						.allowsTightening(true)
			}
		} else {
			let i = (idx - 1) / 2
			let snrColor = getSnrColor(snr: hops[i].snr, preset: modemPreset)
			Image(systemName: "arrowshape.right.fill")
				.resizable()
				.frame(width: idiom == .phone ? 25 : 60, height: idiom == .phone ? 25 : 60)
				.foregroundColor(snrColor.opacity(0.7))
		}
	}
}

func getTraceRouteHops(context: NSManagedObjectContext) -> [TraceRouteHopEntity] {
	///	static let context = PersistenceController.preview.container.viewContext
	var array = [TraceRouteHopEntity]()
	let trh1 = TraceRouteHopEntity(context: context)
	trh1.num = 366311664
	trh1.snr = 12.5
	let trh2 = TraceRouteHopEntity(context: context)
	trh2.num = 3662955168
	trh2.snr = -115.00
	let trh3 = TraceRouteHopEntity(context: context)
	trh3.num = 3663982804
	trh3.snr = 17.5
	let trh4 = TraceRouteHopEntity(context: context)
	trh4.num = 4202719792
	trh4.snr = 7.0
	let trh5 = TraceRouteHopEntity(context: context)
	trh5.num = 603700594
	trh5.snr = 8.9
	let trh6 = TraceRouteHopEntity(context: context)
	trh6.num = 836212501
	trh6.snr = -24.0
	let trh7 = TraceRouteHopEntity(context: context)
	trh7.num = 3663116644
	trh7.snr = -6.0
	let trh8 = TraceRouteHopEntity(context: context)
	trh8.num = 8362955168
	trh8.snr = 7.5
	array.append(trh1)
	array.append(trh2)
	array.append(trh3)
	array.append(trh4)
	array.append(trh5)
	array.append(trh6)
	array.append(trh7)
	array.append(trh8)
	return array
}
