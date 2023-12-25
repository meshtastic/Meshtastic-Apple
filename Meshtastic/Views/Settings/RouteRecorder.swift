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

struct TimerDisplayObject {
	var seconds: Int = 0
	var minutes: Int = 0
	var hours: Int = 0
	
	var display: String {
		if self.seconds == 0 {
			"\(String(format: "%02d", self.hours)):\(String(format: "%02d", self.minutes)):00"
		} else {
			"\(String(format: "%02d", self.hours)):\(String(format: "%02d", self.minutes)):\(String(format: "%02d", self.seconds))"
		}
	}
	
	var timeMinuteCalculator: Float { Float(hours*60+seconds/60+minutes) }
}

@available(iOS 17.0, macOS 14.0, *)
struct RouteRecorder: View {
	
	@ObservedObject var locationsHandler: LocationsHandler = LocationsHandler.shared
	@Environment(\.managedObjectContext) var context
	@State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
	@State var isShowingDetails = false
	@Namespace var namespace
	@Namespace var routerecorderscope
	
	var body: some View {
		VStack {
			VStack {
				Map(position: $position, scope: routerecorderscope) {
					UserAnnotation()
//						ForEach(locations, id: \.id) { location in
//							Marker(location.name, systemImage: location.icon, coordinate: location.location)
//								.tint(location.colour)
//						}
				}
			}
			.mapScope(routerecorderscope)
			.mapControls {
				MapUserLocationButton()
				MapCompass()
				MapScaleView()
				MapPitchToggle()
			}
			.mapStyle(.hybrid(elevation: .realistic, showsTraffic: true))
			.transition(.slide)
			.mapControlVisibility(.visible)
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
							HStack (alignment: .center) {
								Image(systemName: "record.circle.fill")
									.symbolRenderingMode(.multicolor)
									.font(.title3)
									.foregroundColor(.red)
								Text("Recording route - \(locationsHandler.count) locations")
									.font(.title3)
							}
							.padding(.top)
						} else if locationsHandler.isRecordingPaused {
							HStack (alignment: .center) {
								
								Image(systemName: "playpause")
									.symbolRenderingMode(.multicolor)
									.font(.title3)
									.foregroundColor(.red)
								Text("Route recording paused")
									.font(.title3)
							}
							.padding(.top)
						}
						
						
						if locationsHandler.isRecording || locationsHandler.isRecordingPaused {
							Divider()
							HStack {
								VStack {
									Text(locationsHandler.recordingStarted ?? Date(), style: .timer)
										.font(.largeTitle)
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
										.font(.largeTitle)
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
										.font(.largeTitle)
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
							HStack {
								Spacer()
								if !locationsHandler.isRecording && !locationsHandler.isRecordingPaused {
									/// We are not recording or paused, show start recording button a new recording
									Button {
										locationsHandler.isRecording = true
										locationsHandler.count = 0
										locationsHandler.distanceTraveled = 0.0
										locationsHandler.elevationGain = 0.0
										locationsHandler.locationsArray.removeAll()
										locationsHandler.recordingStarted = Date()
									} label: {
										Label("start", systemImage: "start")
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
									/// We are recording show pause button
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
									
									/// We are recording show pause button
									Button {
										locationsHandler.isRecording = false
										locationsHandler.isRecordingPaused = false
										locationsHandler.distanceTraveled = 0.0
										locationsHandler.elevationGain = 0.0
										locationsHandler.locationsArray.removeAll()
										locationsHandler.recordingStarted = nil
									} label: {
										Label("finish", systemImage: "flag.checkered")
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.capsule)
									.controlSize(.large)
									.padding(.bottom)
								}
		
								Button(role: .cancel) {
									isShowingDetails = false
								} label: {
									Label("close", systemImage: "xmark")
								}
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
								.controlSize(.large)
								.padding(.bottom)
								Spacer()
							}
						}
					}
				}
				.presentationDetents([.fraction(0.65)])
				.presentationDragIndicator(.hidden)
				.interactiveDismissDisabled()
			}
		}
	}
}
