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
	
	@ObservedObject var locationsHandler = LocationsHandler.shared
	@Environment(\.managedObjectContext) var context
	@State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
	@State var isTimerRunning = false
	@State var isShowingDetails = false
	@State var timer: Timer?
	@Namespace var namespace
	@Namespace var mapscope
	@State var timeElapsed: TimerDisplayObject = TimerDisplayObject()
	@State var timerDisplay = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
	
	var body: some View {
		VStack {
			VStack {
				VStack {
					Map(position: $position, scope: mapscope) {
						UserAnnotation()
//						ForEach(locations, id: \.id) { location in
//							Marker(location.name, systemImage: location.icon, coordinate: location.location)
//								.tint(location.colour)
//						}
					}
				}
				.mapControls {
					MapUserLocationButton()
					MapCompass()
					MapScaleView()
					MapPitchToggle()
				}
				.mapStyle(.hybrid(elevation: .realistic, showsTraffic: true))
				.transition(.slide)
				.mapControlVisibility(.visible)
				.task {
					print("this is running")
					locationsHandler.startLocationUpdates()
				}
				.safeAreaInset(edge: .bottom) {
					ZStack {
						VStack {
							HStack(spacing: 10) {
								Spacer()
								if isTimerRunning {
									Button {
										isShowingDetails = true
										isTimerRunning = false
									} label: {
										Image(systemName: "pause.fill")
											.frame(width: 60, height: 60)
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.circle)
									.matchedGeometryEffect(id: "Pause Button", in: namespace)
								} else {
									Button {
										isShowingDetails = true
										isTimerRunning = true
										timeElapsed.seconds -= 1
									} label: {
										Image(systemName: "play.fill")
											.frame(width: 60, height: 60)
									}
									.buttonStyle(.bordered)
									.buttonBorderShape(.circle)
									.matchedGeometryEffect(id: "Play Button", in: namespace)
								}
								Spacer()
							}
						}
						.onReceive(timerDisplay) { _ in
							if isTimerRunning {
								timeElapsed.seconds += 1
								if timeElapsed.seconds == 60 {
									timeElapsed.seconds = 0
									timeElapsed.minutes += 1
									if timeElapsed.minutes == 60 {
										timeElapsed.minutes = 0
										timeElapsed.hours += 1
									}
								}
							}
						}
					}
					.padding()
				}
				.sheet(isPresented: $isShowingDetails) {
					NavigationStack {
						VStack {
							HStack {
								Text(timeElapsed.display)
									.font(.largeTitle)
								Text("Time Elapseed")
									.font(.callout)
							}
							.padding()
							Divider()
							VStack(alignment: .leading) {
								let horizontalAccuracy = Measurement(value: locationsHandler.lastLocation.horizontalAccuracy, unit: UnitLength.meters)
								let verticalAccuracy = Measurement(value: locationsHandler.lastLocation.verticalAccuracy, unit: UnitLength.meters)
								let altitiude = Measurement(value: locationsHandler.lastLocation.altitude, unit: UnitLength.meters)
								let speed = Measurement(value: locationsHandler.lastLocation.speed, unit: UnitSpeed.kilometersPerHour)
								List {
									Label("Coordinate \(String(format: "%.5f", locationsHandler.lastLocation.coordinate.latitude)), \(String(format: "%.5f", locationsHandler.lastLocation.coordinate.longitude))", systemImage: "mappin")
										.textSelection(.enabled)
									Label("Horizontal Accuracy \(horizontalAccuracy.formatted())", systemImage: "scope")
									if locationsHandler.lastLocation.verticalAccuracy > 0 {
										Label("Altitude \(altitiude.formatted())", systemImage: "mountain.2")
									}
									Label("Vertical Accuracy \(verticalAccuracy.formatted())", systemImage: "lines.measurement.vertical")
									Label("Satellites Estimate \(LocationHelper.satsInView)", systemImage: "sparkles")
									Label("\(locationsHandler.isStationary ? "Moving" : "Stationary")", systemImage: locationsHandler.isStationary ? "figure.walk.motion" : "figure.stand")
									if locationsHandler.lastLocation.speedAccuracy > 0 {
										Label("Speed \(speed.formatted())", systemImage: "speedometer")
									}
									if locationsHandler.lastLocation.courseAccuracy > 0 {
										/// Heading
										let degrees = Angle.degrees(Double(locationsHandler.lastLocation.course))
										Label {
											let heading = Measurement(value: degrees.degrees, unit: UnitAngle.degrees)
											/// Text("Heading: \(heading.formatted())")
											Text("Heading \(String(format: "%.2f", locationsHandler.lastLocation.course))°")
												.foregroundColor(.primary)
										} icon: {
											Image(systemName: "location.circle")
												.symbolRenderingMode(.hierarchical)
												.frame(width: 35)
												.rotationEffect(degrees)
										}
									}
								}
								.listStyle(.plain)
							}
						}
					}
					.presentationDetents([.fraction(0.6)])
					.presentationDragIndicator(.visible)
				}
			}
		}
	}
}
