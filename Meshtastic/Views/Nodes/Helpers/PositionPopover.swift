//
//  PositionPopover.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/17/23.
//

import SwiftUI
import MapKit

struct PositionPopover: View {
	@Environment(\.dismiss) private var dismiss
	var position: PositionEntity
	var popover: Bool = true
	let distanceFormatter = MKDistanceFormatter()
	var body: some View {
		VStack {
			HStack {
				CircleText(text: position.nodePosition?.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(position.nodePosition?.user?.num ?? 0))), circleSize: 65)
				Spacer()
				Text(position.nodePosition?.user?.longName ?? "Unknown")
					.font(.largeTitle)
				Spacer()
			}
			Divider()
			HStack (alignment: .center) {
				VStack (alignment: .leading) {
					/// Time
					Label {
						Text("heard".localized + ":")
						LastHeardText(lastHeard: position.time)
							.foregroundColor(.primary)
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
					} icon: {
						Image(systemName: "mappin.and.ellipse")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
					/// Altitude
					Label {
						Text("Altitude: \(distanceFormatter.string(fromDistance: Double(position.altitude)))")
							.foregroundColor(.primary)
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
						Text("Heading: \(heading.formatted())")
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "location.north")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
							.rotationEffect(degrees)
					}
					.padding(.bottom, 5)
					/// Speed
					let formatter = MeasurementFormatter()
					Label {
						Text("Speed: \(formatter.string(from: Measurement(value: Double(position.speed), unit: UnitSpeed.kilometersPerHour)))")
						//		.font(.footnote)
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "gauge.with.dots.needle.33percent")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
					
					/// Distance
					if LocationHelper.currentLocation.distance(from: LocationHelper.DefaultLocation) > 0.0 {
						let metersAway = position.coordinate.distance(from: LocationHelper.currentLocation)
						Label {
							Text("distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway)))")
							//		.font(.footnote)
								.foregroundColor(.primary)
						} icon: {
							Image(systemName: "lines.measurement.horizontal")
								.symbolRenderingMode(.hierarchical)
								.frame(width: 35)
						}
					}
				}
				Spacer()
				VStack (alignment: .trailing) {
					if position.nodePosition != nil {
						BatteryGauge(node: position.nodePosition!)
					}
					let mpInt = Int(position.nodePosition?.loRaConfig?.modemPreset ?? 0)
					LoRaSignalStrengthMeter(snr: position.snr, rssi: position.rssi, preset: ModemPresets(rawValue: mpInt) ?? ModemPresets.longFast, compact: false)
				}
			}
			.padding(.top)
			if !popover {
#if targetEnvironment(macCatalyst)
				Spacer()
				Button {
					dismiss()
				} label: {
					Label("close", systemImage: "xmark")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding(.bottom)
#endif
			}
		}
		.presentationDetents([.fraction(0.45), .fraction(0.55), .fraction(0.65)])
		.presentationDragIndicator(.visible)
	}
}
