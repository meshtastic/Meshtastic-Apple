//
//  PositionPopover.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/17/23.
//

import SwiftUI
import MapKit

struct PositionPopover: View {

	@ObservedObject var locationsHandler = LocationsHandler.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.dismiss) private var dismiss
	var position: PositionEntity
	var popover: Bool = true
	let distanceFormatter = MKDistanceFormatter()
	var delay: Double = 0
	@State private var scale: CGFloat = 0.5
	var body: some View {
		// Node Color from node.num
		let nodeColor = UIColor(hex: UInt32(position.nodePosition?.num ?? 0))
		NavigationStack{
		VStack {
			HStack {
				ZStack {
					if position.nodePosition?.isOnline ?? false {
						Circle()
							.fill(Color(nodeColor.lighter()).opacity(0.4).shadow(.drop(color: Color(nodeColor).isLight() ? .black : .white, radius: 5)))
							.foregroundStyle(Color(nodeColor.lighter()).opacity(0.3))
							.scaleEffect(scale)
							.animation(
								Animation.easeInOut(duration: 0.6)
									.repeatForever().delay(delay), value: scale
							)
							.onAppear {
								self.scale = 1
							}
							.frame(width: 90, height: 90)
					}
					CircleText(text: position.nodePosition?.user?.shortName ?? "?", color: Color(nodeColor), circleSize: 65, node: getNodeInfo(id: Int64(position.nodePosition?.user?.num ?? 0), context: context))
				}
				Text(position.nodePosition?.user?.longName ?? "Unknown")
					.font(.largeTitle)
			}
			Divider()
			HStack(alignment: .center) {
				VStack(alignment: .leading) {
					/// Time
					Label {
						if idiom != .phone {
							Text("heard".localized + ":")
						}
						Text(position.time?.lastHeard ?? "unknown")
							.foregroundColor(.primary)
							.font(idiom == .phone ? .callout : .body)
							.allowsTightening(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
					} icon: {
						Image(systemName: position.nodePosition?.isOnline ?? false ? "checkmark.circle.fill" : "moon.circle.fill")
							.symbolRenderingMode(.hierarchical)
							.foregroundColor(position.nodePosition?.isOnline ?? false ? .green : .orange)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
					/// Coordinate
					Label {
						Text("\(String(format: "%.6f", position.coordinate.latitude)), \(String(format: "%.6f", position.coordinate.longitude))")
							.textSelection(.enabled)
							.foregroundColor(.primary)
							.font(idiom == .phone ? .callout : .body)
							.allowsTightening(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
					} icon: {
						Image(systemName: "mappin.and.ellipse")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
					/// Hops Away
					if position.nodePosition?.hopsAway ?? 0 > 0 {
						Label {
							Text("Hops Away: \(position.nodePosition?.hopsAway ?? 0)")
								.textSelection(.enabled)
								.foregroundColor(.primary)
								.font(idiom == .phone ? .callout : .body)
						} icon: {
							Image(systemName: "hare")
								.symbolRenderingMode(.hierarchical)
								.frame(width: 35)
						}
						.padding(.bottom, 5)
					}
					/// Altitude
					Label {
						let distanceInMeters = Measurement(value: Double(position.altitude), unit: UnitLength.meters)
						let distanceInFeet = distanceInMeters.converted(to: UnitLength.feet)
						if Locale.current.measurementSystem == .metric {
							Text(altitudeFormatter.string(from: distanceInMeters))
								.foregroundColor(.primary)
								.font(idiom == .phone ? .callout : .body)
						} else {
							Text(altitudeFormatter.string(from: distanceInFeet))
								.foregroundColor(.primary)
								.font(idiom == .phone ? .callout : .body)
						}
						
					} icon: {
						Image(systemName: "mountain.2.fill")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
					let pf = PositionFlags(rawValue: Int(position.nodePosition?.metadata?.positionFlags ?? 3))
					/// Sats in view
					if pf.contains(.Satsinview) {
						Label {
							Text("Sats in view: \(String(position.satsInView))")
								.foregroundColor(.primary)
								.font(idiom == .phone ? .callout : .body)
						} icon: {
							Image(systemName: "sparkles")
								.symbolRenderingMode(.hierarchical)
								.frame(width: 35)
						}
						.padding(.bottom, 5)
					}
					/// Sequence Number
					if pf.contains(.SeqNo) {
						Label {
							Text("Sequence: \(String(position.seqNo))")
								.foregroundColor(.primary)
								.font(idiom == .phone ? .callout : .body)
						} icon: {
							Image(systemName: "number")
								.symbolRenderingMode(.hierarchical)
								.frame(width: 35)
						}
						.padding(.bottom, 5)
					}
					/// Heading
					let degrees = Angle.degrees(Double(position.heading))
					Label {
						let heading = Measurement(value: degrees.degrees, unit: UnitAngle.degrees)
						Text("Heading: \(heading.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0)))))")
					} icon: {
						Image(systemName: "location.north")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
							.rotationEffect(degrees)
					}
					.padding(.bottom, 5)
					/// Distance
					if let lastLocation = locationsHandler.locationsArray.last {
						/// Distance
						if lastLocation.distance(from: CLLocation(latitude: LocationsHandler.DefaultLocation.latitude, longitude: LocationsHandler.DefaultLocation.longitude)) > 0.0 {
							let metersAway = position.coordinate.distance(from: CLLocationCoordinate2D(latitude: lastLocation.coordinate.latitude, longitude: lastLocation.coordinate.longitude))
							Label {
								Text("distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway)))")
									.foregroundColor(.primary)
									.font(idiom == .phone ? .callout : .body)
							} icon: {
								Image(systemName: "lines.measurement.horizontal")
									.symbolRenderingMode(.hierarchical)
									.frame(width: 35)
							}
						}
					}
					/// Speed
					let speed = Measurement(value: Double(position.speed), unit: UnitSpeed.kilometersPerHour)
					Label {
						Text("Speed: \(speed.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))")
							.foregroundColor(.primary)
							.font(idiom == .phone ? .callout : .body)
					} icon: {
						Image(systemName: "gauge.with.dots.needle.33percent")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
					if position.nodePosition?.viaMqtt ?? false {
						
						Label {
							Text("MQTT")
								.font(idiom == .phone ? .callout : .body)
						} icon: {
							Image(systemName: "network")
								.symbolRenderingMode(.hierarchical)
								.frame(width: 35)
								.rotationEffect(degrees)
						}
						.padding(.bottom, 5)
					}
					Spacer()
				}
				Spacer()
				VStack(alignment: .center) {
					if position.nodePosition != nil {
						if position.nodePosition?.favorite ?? false {
							Image(systemName: "star.fill")
								.foregroundColor(.yellow)
								.symbolRenderingMode(.hierarchical)
								.font(.largeTitle)
								.padding(.bottom, 5)
						}
						if position.nodePosition?.hasEnvironmentMetrics ?? false {
							Image(systemName: "cloud.sun.rain")
								.foregroundColor(.accentColor)
								.symbolRenderingMode(.multicolor)
								.font(.largeTitle)
								.padding(.bottom)
						}
						if position.nodePosition?.hasDetectionSensorMetrics ?? false {
							Image(systemName: "sensor.fill")
								.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
								.symbolRenderingMode(.hierarchical)
								.foregroundColor(.accentColor)
								.font(.largeTitle)
								.padding(.bottom)
						}
						BatteryGauge(node: position.nodePosition!)
					}
					if position.nodePosition?.hopsAway ?? 0 == 0 && !(position.nodePosition?.viaMqtt ?? false) {
						LoRaSignalStrengthMeter(snr: position.nodePosition?.snr ?? 0.0, rssi: position.nodePosition?.rssi ?? 0, preset: ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast, compact: false)
					}
					Spacer()
				}
			}
			.padding(.top)
			if !popover {
#if targetEnvironment(macCatalyst)
				Spacer()
				Button {
					dismiss()
				} label: {
					Label("Close", systemImage: "xmark")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding(.bottom)
#endif
			}
		}
	}
		.presentationDetents([.fraction(0.65), .large])
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .large))
	}
}
