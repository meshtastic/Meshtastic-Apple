import FirebaseAnalytics
import MapKit
import SwiftUI

struct TraceRoute: View {
	@ObservedObject
	var node: NodeInfoEntity

	private let distanceFormatter = MKDistanceFormatter()
	private let dateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short

		return formatter
	}()

	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@State
	private var isPresentingClearLogConfirm: Bool = false
	@State
	private var selectedRoute: TraceRouteEntity?
	@State
	private var mapStyle = MapStyle.standard(
		elevation: .realistic,
		emphasis: MapStyle.StandardEmphasis.muted
	)
	@State
	private var position = MapCameraPosition.automatic
	@Namespace
	private var mapScope

	private var routes: [TraceRouteEntity]? {
		guard let routes = node.traceRoutes else {
			return nil
		}

		return routes.reversed() as? [TraceRouteEntity]
	}

	@ViewBuilder
	var body: some View {
		HStack(alignment: .top) {
			VStack {
				if let routes {
					List {
						Button {
							_ = bleManager.sendTraceRouteRequest(
								destNum: node.user?.num ?? 0,
								wantResponse: true
							)
						} label: {
							Label {
								Text("Request new")
							} icon: {
								Image(systemName: "arrow.clockwise")
									.symbolRenderingMode(.monochrome)
									.foregroundColor(.accentColor)
							}
						}

						ForEach(routes, id: \.num) { (route: TraceRouteEntity) in
							ZStack {
								traceRoute(for: route)
							}
							.onTapGesture {
								selectedRoute = route
							}
						}
					}
					.listStyle(.automatic)
					.onAppear {
						selectedRoute = routes.first
					}
				}

				if let selectedRoute {
					VStack {
						if selectedRoute.response && selectedRoute.hops?.count ?? 0 > 0 {
							Label {
								Text("Route: \(selectedRoute.routeText ?? "N/A")")
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title2)
						}
						else if selectedRoute.response {
							Label {
								Text("Trace route received directly by \(selectedRoute.node?.user?.longName ?? "N/A")")
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title2)
						}

						if selectedRoute.response {
							if selectedRoute.hasPositions {
								Map(
									position: $position,
									bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity),
									scope: mapScope
								) {
									Annotation(
										"You",
										coordinate: selectedRoute.coordinate ?? LocationManager.defaultLocation.coordinate
									) {
										ZStack {
											Circle()
												.fill(Color(.green))
												.strokeBorder(.white, lineWidth: 3)
												.frame(width: 15, height: 15)
										}
									}
									.annotationTitles(.automatic)

									// Direct Trace Route
									if selectedRoute.response && selectedRoute.hops?.count ?? 0 == 0 {
										if
											selectedRoute.node?.positions?.count ?? 0 > 0,
											let mostRecent = selectedRoute.node?.positions?.lastObject as? PositionEntity
										{
											let traceRouteCoords: [CLLocationCoordinate2D] = [
												selectedRoute.coordinate ?? LocationManager.defaultLocation.coordinate,
												mostRecent.coordinate
											]
											Annotation(
												selectedRoute.node?.user?.shortName ?? "???",
												coordinate: mostRecent.nodeCoordinate ?? LocationManager.defaultLocation.coordinate
											) {
												ZStack {
													Circle()
														.fill(Color(.black))
														.strokeBorder(.white, lineWidth: 3)
														.frame(width: 15, height: 15)
												}
											}

											let dashed = StrokeStyle(
												lineWidth: 2,
												lineCap: .round,
												lineJoin: .round,
												dash: [7, 10]
											)
											MapPolyline(coordinates: traceRouteCoords)
												.stroke(.blue, style: dashed)
										}
									}
								}
								.frame(maxWidth: .infinity, maxHeight: .infinity)
							}

							VStack {
								/// Distance
								if selectedRoute.node?.positions?.count ?? 0 > 0,
								   selectedRoute.coordinate != nil,
								   let mostRecent = selectedRoute.node?.positions?.lastObject as? PositionEntity {

									let startPoint = CLLocation(
										latitude: selectedRoute.coordinate?.latitude ?? LocationManager.defaultLocation.coordinate.latitude,
										longitude: selectedRoute.coordinate?.longitude ?? LocationManager.defaultLocation.coordinate.longitude
									)

									if startPoint.distance(
										from: CLLocation(
											latitude: LocationManager.defaultLocation.coordinate.latitude,
											longitude: LocationManager.defaultLocation.coordinate.longitude)
									)
										> 0.0 {
										let metersAway = selectedRoute.coordinate?.distance(
											from: CLLocationCoordinate2D(
												latitude: mostRecent.latitude ?? LocationManager.defaultLocation.coordinate.latitude,
												longitude: mostRecent.longitude ?? LocationManager.defaultLocation.coordinate.longitude
											)
										)

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
						}
						else {
							VStack {
								Label {
									Text("Trace route sent to \(selectedRoute.node?.user?.longName ?? "unknown".localized)")
								} icon: {
									Image(systemName: "signpost.right.and.left")
										.symbolRenderingMode(.hierarchical)
								}
								.font(.title3)

								Spacer()
							}
						}
					}
				}
				else {
					ContentUnavailableView("No Trace Route Selected", systemImage: "signpost.right.and.left")
				}
			}
		}
		.navigationTitle("Trace Route")
		.navigationBarItems(
			trailing: ConnectedDevice()
		)
		.onAppear {
			Analytics.logEvent(AnalyticEvents.traceRoute.id, parameters: [:])
		}
	}

	@ViewBuilder
	private func traceRoute(for route: TraceRouteEntity) -> some View {
		let hops = route.hops?.array as? [TraceRouteHopEntity]
		let hopCount = hops?.count

		Label {
			VStack(alignment: .leading, spacing: 4) {
				if route.response {
					if let hopCount {
						if hopCount == 0 {
							Text("Direct")
								.font(.body)
						}
						else {
							Text("\(hopCount) hop(s)")
								.font(.body)

							if let hops {
								Spacer()
									.frame(height: 4)

								ForEach(hops, id: \.num) { hop in
									HStack(alignment: .center, spacing: 4) {
										Image(systemName: "hare")
											.font(.system(size: 10))
											.foregroundColor(.gray)
											.frame(width: 24)

										Text(hop.name ?? "Unknown node")
											.font(.system(size: 10))
											.foregroundColor(.gray)
									}
								}

								if let destination = node.user?.longName {
									HStack(alignment: .center, spacing: 4) {
										Image(systemName: "target")
											.font(.system(size: 10))
											.foregroundColor(.gray)
											.frame(width: 24)

										Text(destination)
											.font(.system(size: 10))
											.foregroundColor(.gray)
									}
								}
							}
						}
					}
					else {
						Text("N/A")
							.font(.body)
					}
				}
				else {
					Text("No Response")
						.font(.body)
				}

				if let time = route.time {
					HStack(spacing: 4) {
						Spacer()

						Text(dateFormatter.string(from: time))
							.font(.system(size: 10))
							.foregroundColor(.gray)
					}
				}
			}
		} icon: {
			if route.response {
				if let hopCount {
					if hopCount == 0 {
						routeIcon(name: "person.line.dotted.person.fill")
					}
					else {
						routeIcon(name: "person.2.wave.2.fill")
					}
				}
				else {
					routeIcon(name: "person.fill.questionmark")
				}
			}
			else {
				routeIcon(name: "person.slash.fill")
			}
		}
	}

	@ViewBuilder
	private func routeIcon(name: String) -> some View {
		Image(systemName: name)
			.resizable()
			.scaledToFit()
			.frame(width: 32, height: 32)
	}
}
