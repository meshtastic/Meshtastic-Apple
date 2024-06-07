//
//  Routes.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 11/21/23.
//

import SwiftUI
import CoreData
import MapKit
import CoreLocation
import CoreMotion
import OSLog

@available(iOS 17.0, macOS 14.0, *)
struct RouteRecorder: View {

	@ObservedObject var locationsHandler: LocationsHandler = LocationsHandler.shared
	@Environment(\.managedObjectContext) var context
	@State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .realistic)
	@State var isShowingDetails = false
	@Namespace var namespace
	@Namespace var routerecorderscope
	@State var recording: RouteEntity?
	@State var color: Color = .blue
	@State var activity: Int = 1

	var body: some View {
		VStack {
			ZStack {
				Map(position: $position, scope: routerecorderscope) {
					UserAnnotation()
					/// Route Lines
					let lineCoords = locationsHandler.locationsArray.compactMap({(position) -> CLLocationCoordinate2D in
						return position.coordinate
					})

					let gradient = LinearGradient(
						colors: [color],
						startPoint: .leading, endPoint: .trailing
					)
					let dashed = StrokeStyle(
						lineWidth: 3,
						lineCap: .round, lineJoin: .round, dash: [10, 10]
					)
					MapPolyline(coordinates: lineCoords)
						.stroke(gradient, style: dashed)

				}
				.mapStyle(mapStyle)
			}
			.mapScope(routerecorderscope)
			.safeAreaInset(edge: .bottom) {
				ZStack {
					VStack {
						HStack(spacing: 10) {
							Spacer()

							Button {
								isShowingDetails = true
							} label: {
								Image(systemName: locationsHandler.isRecording ? "record.circle.fill" : "record.circle")
									.font(.system(size: 72))
									.symbolRenderingMode(.multicolor)
									.foregroundColor(.red)
							}
							.buttonStyle(.bordered)
							.foregroundColor(.red)
							.buttonBorderShape(.circle)
							.matchedGeometryEffect(id: "Details Button", in: namespace)

							Spacer()
						}
					}
				}
				.padding()
			}
			.sheet(isPresented: $isShowingDetails) {
				NavigationStack {
					VStack {
						if locationsHandler.isRecording {
							HStack(alignment: .center) {
								Image(systemName: "record.circle.fill")
									.symbolRenderingMode(.multicolor)
									.font(.title)
									.foregroundColor(.red)
								Text("Recording route")
									.font(.title)
								Spacer()
								Text("\(Image(systemName: "mappin.and.ellipse")) \(locationsHandler.count)")
									.foregroundColor(.red)
									.font(.title2)
							}
							.padding()
						} else if locationsHandler.isRecordingPaused {
							HStack(alignment: .center) {

								Image(systemName: "playpause")
									.symbolRenderingMode(.multicolor)
									.font(.title3)
									.foregroundColor(.red)
								Text("Route recording paused")
									.font(.title)
							}
							.padding(.top)
						}

						if locationsHandler.isRecording || locationsHandler.isRecordingPaused {
							Divider()
							HStack {
								VStack {
									Text(locationsHandler.recordingStarted ?? Date(), style: .timer)
										.font(.title)
										.fixedSize()
									Text("Time")
										.font(.callout)
										.fixedSize()
								}
								.padding(.horizontal)
								Divider()
								VStack {
									let distance = Measurement(value: locationsHandler.distanceTraveled, unit: UnitLength.meters)
									Text("\(distance.formatted())")
										.font(.title)
										.fixedSize()
									Text("Distance")
										.font(.callout)
										.fixedSize()
								}
								.padding(.horizontal)
								Divider()
								VStack {
									let gain = Measurement(value: locationsHandler.elevationGain, unit: UnitLength.meters)
									Text(gain.formatted())
										.font(.title)
									Text("Elev. Gain")
										.font(.callout)
								}
								.padding(.horizontal)
							}
							.frame(maxHeight: 90)
						}
						Divider()
						VStack(alignment: .leading) {
							List {
								GPSStatus(largeFont: .body, smallFont: .callout)
							}
							.listStyle(.plain)
							if recording == nil {
								HStack(alignment: .center) {
									Spacer()
									Image(systemName: "figure.hiking")
										.symbolRenderingMode(.multicolor)
										.font(.title3)
										.foregroundColor(.accentColor)
									Text("activity")
									Picker(selection: $activity, label: Text("Activity")) {
										ForEach(ActivityType.allCases) { r in
											Text(r.description)
										}
									}
									Spacer()
								}
							}
							HStack {
								Spacer()
								if !locationsHandler.isRecording && !locationsHandler.isRecordingPaused {
									/// We are not recording or paused, show start recording button
									Button {
										locationsHandler.isRecording = true
										locationsHandler.count = 0
										locationsHandler.distanceTraveled = 0.0
										locationsHandler.elevationGain = 0.0
										locationsHandler.locationsArray.removeAll()
										locationsHandler.recordingStarted = Date()
										let newRoute = RouteEntity(context: context)
										newRoute.date = Date()
										let at = ActivityType(rawValue: activity)
										newRoute.name = "\(newRoute.date?.relativeTimeOfDay() ?? "morning".localized) \(at?.fileNameString ?? "hike")"
										newRoute.id = Int32.random(in: Int32(Int8.max) ... Int32.max)
										newRoute.color = Int64(UIColor.random.hex)
										newRoute.enabled = false
										color = Color(UIColor(hex: UInt32(newRoute.color)))
										self.recording = newRoute
										do {
											try context.save()
											Logger.data.info("💾 Saved a new route")
										} catch {
											context.rollback()
											let nsError = error as NSError
											Logger.data.error("Error Saving RouteEntity from the Route Recorder \(nsError)")
										}
									} label: {
										Label("start", systemImage: "play")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding(.bottom)

								} else if locationsHandler.isRecording {
									/// We are recording show pause button
									Button {
										locationsHandler.isRecording = false
										locationsHandler.isRecordingPaused = true
									} label: {
										Label("pause", systemImage: "pause")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding(.bottom)
								} else if locationsHandler.isRecordingPaused {
									/// We are paused show resume button
									Button {
										locationsHandler.isRecording = true
										locationsHandler.isRecordingPaused = false
									} label: {
										Label("resume", systemImage: "playpause")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding(.bottom)
								}

								if locationsHandler.isRecording || locationsHandler.isRecordingPaused {
									/// We are recording or paused, show finish button
									Button {

										if let rec = recording {
											rec.enabled = true
											rec.distance = locationsHandler.distanceTraveled
											rec.elevationGain = locationsHandler.elevationGain
											context.refresh(rec, mergeChanges: true)
										}
										locationsHandler.isRecording = false
										locationsHandler.isRecordingPaused = false
										locationsHandler.distanceTraveled = 0.0
										locationsHandler.elevationGain = 0.0
										locationsHandler.locationsArray.removeAll()
										locationsHandler.recordingStarted = nil
										do {
											try context.save()
											Logger.data.info("💾 Saved a route finish")
										} catch {
											context.rollback()
											let nsError = error as NSError
											Logger.data.error("Error Saving RouteEntity from the Route Recorder \(nsError)")
										}
										isShowingDetails = false
									} label: {
										Label("finish", systemImage: "flag.checkered")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding(.bottom)
								}
#if targetEnvironment(macCatalyst)
								Button(role: .cancel) {
									isShowingDetails = false
								} label: {
									Label("close", systemImage: "xmark")
								}
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
								.controlSize(.large)
								.padding(.bottom)
#endif
								Spacer()
							}

						}
					}
				}
				.presentationDetents([.fraction(0.45), .fraction(0.65)])
				.presentationDragIndicator(.hidden)
				.interactiveDismissDisabled(false)
				.onAppear {
					UIApplication.shared.isIdleTimerDisabled = true
				}
				.onDisappear(perform: {
					UIApplication.shared.isIdleTimerDisabled = false
				})
				.onChange(of: locationsHandler.locationsArray.last) { location in
					guard locationsHandler.isRecording, let location, let recording else { return }
					let locationEntity = LocationEntity(
						context: context,
						route: recording,
						id: Int32(locationsHandler.count),
						location: location
					)
					
					do {
						try context.save()
						Logger.data.info("💾 Saved a new route location")
					} catch {
						context.rollback()
						let nsError = error as NSError
						Logger.data.error("Error Saving LocationEntity from the Route Recorder \(nsError)")
					}
				}
			}
		}
		.ignoresSafeArea(.all, edges: [.top, .leading, .trailing])
	}
}
