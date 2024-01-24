////
////  Routes.swift
////  Meshtastic
////
////  Created by Garth Vander Houwen on 11/21/23.
////
//
//import SwiftUI
//import CoreData
//import MapKit
//import CoreLocation
//import CoreMotion
//
//@available(iOS 17.0, macOS 14.0, *)
//struct RouteRecorder: View {
//	
//	@ObservedObject var locationsHandler: LocationsHandler = LocationsHandler.shared
//	@Environment(\.managedObjectContext) var context
//	@State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
//	//@State var mapStyle: MapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: .all, showsTraffic: true)
//	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .realistic)
//	@State var isShowingDetails = false
//	@Namespace var namespace
//	@Namespace var routerecorderscope
//	@State var recording: RouteEntity?
//	@State var color: Color = .blue
//	
//	var body: some View {
//		VStack {
//			ZStack {
//				Map(position: $position, scope: routerecorderscope) {
//					UserAnnotation()
//					/// Route Lines
//					let lineCoords = locationsHandler.locationsArray.compactMap({(position) -> CLLocationCoordinate2D in
//						return position.coordinate
//					})
//					
//					let gradient = LinearGradient(
//						colors: [color],
//						startPoint: .leading, endPoint: .trailing
//					)
//					let dashed = StrokeStyle(
//						lineWidth: 3,
//						lineCap: .round, lineJoin: .round, dash: [10, 10]
//					)
//					MapPolyline(coordinates: lineCoords)
//						.stroke(gradient, style: dashed)
//
//				}
//				.mapStyle(mapStyle)
//			}
//			.mapScope(routerecorderscope)
//			.safeAreaInset(edge: .bottom) {
//				ZStack {
//					VStack {
//						HStack(spacing: 10) {
//							Spacer()
//
//							Button {
//								isShowingDetails = true
//							} label: {
//								Image(systemName: locationsHandler.isRecording ? "record.circle.fill" : "record.circle")
//									.font(.system(size: 72))
//									.symbolRenderingMode(.multicolor)
//									.foregroundColor(.red)
//							}
//							.buttonStyle(.bordered)
//							.foregroundColor(.red)
//							.buttonBorderShape(.circle)
//							.matchedGeometryEffect(id: "Details Button", in: namespace)
//
//							Spacer()
//						}
//					}
//				}
//				.padding()
//			}
//			.sheet(isPresented: $isShowingDetails) {
//				NavigationStack {
//					VStack {
//						if locationsHandler.isRecording {
//							HStack (alignment: .center) {
//								Image(systemName: "record.circle.fill")
//									.symbolRenderingMode(.multicolor)
//									.font(.title)
//									.foregroundColor(.red)
//								Text("Recording route")
//									.font(.title)
//								Spacer()
//								Text("\(locationsHandler.count)")
//									.foregroundColor(.red)
//									.font(.title2)
//							}
//							.padding()
//						} else if locationsHandler.isRecordingPaused {
//							HStack (alignment: .center) {
//								
//								Image(systemName: "playpause")
//									.symbolRenderingMode(.multicolor)
//									.font(.title3)
//									.foregroundColor(.red)
//								Text("Route recording paused")
//									.font(.title)
//							}
//							.padding(.top)
//						}
//						
//						if locationsHandler.isRecording || locationsHandler.isRecordingPaused {
//							Divider()
//							HStack {
//								VStack {
//									Text(locationsHandler.recordingStarted ?? Date(), style: .timer)
//										.font(.title)
//										.fixedSize()
//									Text("Time")
//										.font(.callout)
//										.fixedSize()
//								}
//								.padding(.horizontal)
//								Divider()
//								VStack {
//									let distance = Measurement(value: locationsHandler.distanceTraveled, unit: UnitLength.meters)
//									Text("\(distance.formatted())")
//										.font(.title)
//										.fixedSize()
//									Text("Distance")
//										.font(.callout)
//										.fixedSize()
//								}
//								.padding(.horizontal)
//								Divider()
//								VStack {
//									let gain = Measurement(value: locationsHandler.elevationGain, unit: UnitLength.meters)
//									Text(gain.formatted())
//										.font(.title)
//									Text("Elev. Gain")
//										.font(.callout)
//								}
//								.padding(.horizontal)
//							}
//							.frame(maxHeight: 90)
//						}
//						Divider()
//						VStack(alignment: .leading) {
//							List {
//								GPSStatus(largeFont: .body, smallFont: .callout)
//							}
//							.listStyle(.plain)
//							HStack {
//								Spacer()
//								if !locationsHandler.isRecording && !locationsHandler.isRecordingPaused {
//									/// We are not recording or paused, show start recording button
//									Button {
//										locationsHandler.isRecording = true
//										locationsHandler.count = 0
//										locationsHandler.distanceTraveled = 0.0
//										locationsHandler.elevationGain = 0.0
//										locationsHandler.locationsArray.removeAll()
//										locationsHandler.recordingStarted = Date()
//										let newRoute = RouteEntity(context: context)
//										newRoute.name = String("Route Recording")
//										newRoute.id = Int32.random(in: Int32(Int8.max) ... Int32.max)
//										newRoute.color = Int64(UIColor.random.hex)
//										newRoute.date = Date()
//										newRoute.enabled = false
//										color = Color(UIColor(hex: UInt32(newRoute.color)))
//										self.recording = newRoute
//										do {
//											try context.save()
//											print("💾 Saved a new route")
//										} catch {
//											context.rollback()
//											let nsError = error as NSError
//											print("💥 Error Saving RouteEntity from the Route Recorder \(nsError)")
//										}
//									} label: {
//										Label("start", systemImage: "play")
//									}
//									.buttonStyle(.bordered)
//									.buttonBorderShape(.capsule)
//									.controlSize(.large)
//									.padding(.bottom)
//									
//								} else if locationsHandler.isRecording {
//									/// We are recording show pause button
//									Button {
//										locationsHandler.isRecording = false
//										locationsHandler.isRecordingPaused = true
//									} label: {
//										Label("pause", systemImage: "pause")
//									}
//									.buttonStyle(.bordered)
//									.buttonBorderShape(.capsule)
//									.controlSize(.large)
//									.padding(.bottom)
//								} else if locationsHandler.isRecordingPaused {
//									/// We are paused show resume button
//									Button {
//										locationsHandler.isRecording = true
//										locationsHandler.isRecordingPaused = false
//									} label: {
//										Label("resume", systemImage: "playpause")
//									}
//									.buttonStyle(.bordered)
//									.buttonBorderShape(.capsule)
//									.controlSize(.large)
//									.padding(.bottom)
//								}
//								
//								if locationsHandler.isRecording || locationsHandler.isRecordingPaused {
//									/// We are recording or paused, show finish button
//									Button {
//										locationsHandler.isRecording = false
//										locationsHandler.isRecordingPaused = false
//										locationsHandler.distanceTraveled = 0.0
//										locationsHandler.elevationGain = 0.0
//										locationsHandler.locationsArray.removeAll()
//										locationsHandler.recordingStarted = nil
//										if let rec = recording {
//											rec.enabled = true
//											context.refresh(rec, mergeChanges:true)
//										}
//										
//										do {
//											try context.save()
//											print("💾 Saved a route finish")
//										} catch {
//											context.rollback()
//											let nsError = error as NSError
//											print("💥 Error Saving RouteEntity from the Route Recorder \(nsError)")
//										}
//									} label: {
//										Label("finish", systemImage: "flag.checkered")
//									}
//									.buttonStyle(.bordered)
//									.buttonBorderShape(.capsule)
//									.controlSize(.large)
//									.padding(.bottom)
//								}
//#if targetEnvironment(macCatalyst)
//								Button(role: .cancel) {
//									isShowingDetails = false
//								} label: {
//									Label("close", systemImage: "xmark")
//								}
//								.buttonStyle(.bordered)
//								.buttonBorderShape(.capsule)
//								.controlSize(.large)
//								.padding(.bottom)
//#endif
//								Spacer()
//							}
//							
//						}
//					}
//				}
//				.presentationDetents([.fraction(0.30), .fraction(0.65)])
//				.presentationDragIndicator(.hidden)
//				.interactiveDismissDisabled(false)
//				.onAppear {
//					UIApplication.shared.isIdleTimerDisabled = true
//				}
//				.onDisappear(perform: {
//					UIApplication.shared.isIdleTimerDisabled = false
//				})
//				.onChange(of: locationsHandler.locationsArray.last) { newLoc in
//					if locationsHandler.isRecording {
//						if let loc = newLoc {
//							if recording != nil {
//								let locationEntity = LocationEntity(context: context)
//								locationEntity.routeLocation = recording
//								locationEntity.id = Int32(locationsHandler.count)
//								locationEntity.altitude = Int32(loc.altitude)
//								locationEntity.heading = Int32(loc.course)
//								locationEntity.speed = Int32(loc.speed)
//								locationEntity.latitudeI = Int32(loc.coordinate.latitude * 1e7)
//								locationEntity.longitudeI = Int32(loc.coordinate.longitude * 1e7)
//								do {
//									try context.save()
//									print("💾 Saved a new route location")
//									//print("💾 Updated Canned Messages Messages For: \(fetchedNode[0].num)")
//								} catch {
//									context.rollback()
//									let nsError = error as NSError
//									print("💥 Error Saving LocationEntity from the Route Recorder \(nsError)")
//								}
//							}
//						}
//					}
//				}
//			}
//		}
//		.ignoresSafeArea(.all, edges: [.top, .leading, .trailing])
//	}
//}
