//
//  NodeListItem.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//

import SwiftUI
import CoreLocation

struct NodeListItem: View {

	@ObservedObject var node: NodeInfoEntity
	var connected: Bool
	var connectedNode: Int64
	var modemPreset: ModemPresets = ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast

	var body: some View {

		NavigationLink(value: node) {
			LazyVStack(alignment: .leading) {
				HStack {
					VStack(alignment: .leading) {
						CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 70)
							.padding(.trailing, 5)
						if node.latestDeviceMetrics != nil {
							BatteryCompact(batteryLevel: node.latestDeviceMetrics?.batteryLevel ?? 0, font: .caption, iconFont: .callout, color: .accentColor)
								.padding(.trailing, 5)
						}
					}
					VStack(alignment: .leading) {
						HStack {
							if node.user?.pkiEncrypted ?? false {
								if !(node.user?.keyMatch ?? false) {
									/// Public Key on the User and the Public Key on the Last Message don't match
									Image(systemName: "key.slash")
										.foregroundColor(.red)
								} else {
									Image(systemName: "lock.fill")
										.foregroundColor(.green)
								}
							} else {
								Image(systemName: "lock.open.fill")
									.foregroundColor(.yellow)
							}
							Text(node.user?.longName ?? "unknown".localized)
								.font(.headline)
								.fontWeight(.regular)
								.allowsTightening(true)
							if node.favorite {
								Spacer()
								Image(systemName: "star.fill")
									.symbolRenderingMode(.multicolor)
							}
						}
						if connected {
							HStack {
								Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
									.font(.callout)
									.symbolRenderingMode(.hierarchical)
									.foregroundColor(.green)
									.frame(width: 30)
								Text("connected")
									.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
									.foregroundColor(.gray)
							}
						}
						HStack {
							Image(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill")
								.font(.callout)
								.symbolRenderingMode(.hierarchical)
								.foregroundColor(node.isOnline ? .green : .orange)
								.frame(width: 30)
							LastHeardText(lastHeard: node.lastHeard)
								.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
								.foregroundColor(.gray)
						}
						HStack {
							let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
							Image(systemName: role?.systemName ?? "figure")
								.font(.callout)
								.symbolRenderingMode(.hierarchical)
								.frame(width: 30)
							Text("Role: \(role?.name ?? "unknown".localized)")
								.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
								.foregroundColor(.gray)

						}
						if node.isStoreForwardRouter {
							HStack {
								Image(systemName: "envelope.arrow.triangle.branch")
									.font(.callout)
									.symbolRenderingMode(.multicolor)
									.frame(width: 30)
								Text("storeforward".localized)
									.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
									.foregroundColor(.secondary)
							}
						}

						if node.positions?.count ?? 0 > 0 && connectedNode != node.num {
							HStack {
								if let lastPostion = node.positions?.lastObject as? PositionEntity {
									if let currentLocation = LocationsHandler.shared.locationsArray.last {
										let myCoord = CLLocation(latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude)
										if lastPostion.nodeCoordinate != nil && myCoord.coordinate.longitude != LocationsHandler.DefaultLocation.longitude && myCoord.coordinate.latitude != LocationsHandler.DefaultLocation.latitude {
											let nodeCoord = CLLocation(latitude: lastPostion.nodeCoordinate!.latitude, longitude: lastPostion.nodeCoordinate!.longitude)
											let metersAway = nodeCoord.distance(from: myCoord)
											Image(systemName: "lines.measurement.horizontal")
												.font(.callout)
												.symbolRenderingMode(.multicolor)
												.frame(width: 30)
											DistanceText(meters: metersAway)
												.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
												.foregroundColor(.gray)
											let trueBearing = getBearingBetweenTwoPoints(point1: myCoord, point2: nodeCoord)
											let headingDegrees = Measurement(value: trueBearing, unit: UnitAngle.degrees)
											Image(systemName: "location.north")
												.font(.callout)
												.symbolRenderingMode(.multicolor)
												.clipShape(Circle())
												.rotationEffect(Angle(degrees: headingDegrees.value))
											let heading = Measurement(value: trueBearing, unit: UnitAngle.degrees)
											Text("\(heading.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0)))))")
												.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
												.foregroundColor(.gray)
										}
									}
								}
							}
						}
						HStack {
							if node.channel > 0 {
								HStack {
									Image(systemName: "\(node.channel).circle.fill")
										.font(.title2)
										.frame(width: 30)
									Text("Channel")
										.foregroundColor(.secondary)
										.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
								}
							}

							if node.viaMqtt && connectedNode != node.num {
								Image(systemName: "dot.radiowaves.up.forward")
									.symbolRenderingMode(.multicolor)
									.font(.callout)
									.frame(width: 30)
								Text("MQTT")
									.foregroundColor(.gray)
									.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
							}
						}
						if node.hasPositions || node.hasEnvironmentMetrics || node.hasDetectionSensorMetrics || node.hasTraceRoutes {
							HStack {
								Image(systemName: "scroll")
									.symbolRenderingMode(.hierarchical)
									.font(.callout)
								Text("Logs:")
									.foregroundColor(.gray)
									.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption2)
									.allowsTightening(true)
								if node.hasDeviceMetrics {
									Image(systemName: "flipphone")
										.symbolRenderingMode(.hierarchical)
										.font(.callout)
								}
								if node.hasPositions {
									Image(systemName: "mappin.and.ellipse")
										.symbolRenderingMode(.hierarchical)
										.font(.callout)

								}
								if node.hasEnvironmentMetrics {
									Image(systemName: "cloud.sun.rain")
										.symbolRenderingMode(.hierarchical)
										.font(.callout)

								}
								if node.hasDetectionSensorMetrics {
									Image(systemName: "sensor")
										.symbolRenderingMode(.hierarchical)
										.font(.callout)
								}
								if node.hasTraceRoutes {
									Image(systemName: "signpost.right.and.left")
										.symbolRenderingMode(.hierarchical)
										.font(.callout)
								}
							}
						}
						if node.hopsAway > 0 {
							HStack {
								Image(systemName: "hare")
									.font(.callout)
									.symbolRenderingMode(.multicolor)
								Text("Hops Away:")
									.foregroundColor(.secondary)
									.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
								Image(systemName: "\(node.hopsAway).square")
									.font(.title2)
							}
						} else {
							if node.snr != 0 && !node.viaMqtt {
								LoRaSignalStrengthMeter(snr: node.snr, rssi: node.rssi, preset: modemPreset, compact: true)
									.padding(.top, node.hasPositions || node.hasEnvironmentMetrics || node.hasDetectionSensorMetrics || node.hasTraceRoutes ? 0 : 15)
							}
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
			}
		}
		.padding(.top, 4)
		.padding(.bottom, 4)
	}
}
