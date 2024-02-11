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
	var modemPreset: Int
	
	var body: some View {
		
		NavigationLink(value: node) {
			LazyVStack(alignment: .leading) {
				HStack {
					VStack(alignment: .leading) {
						CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 65)
							.padding(.trailing, 5)
					}
					VStack(alignment: .leading) {
						HStack {
							Text(node.user?.longName ?? "unknown".localized)
								.fontWeight(.medium)
								.font(.headline)
							if node.user?.vip ?? false {
								Spacer()
								Image(systemName: "star.fill")
									.foregroundColor(.yellow)
							}
						}
						if connected {
							HStack {
								Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
									.font(.callout)
									.symbolRenderingMode(.hierarchical)
									.foregroundColor(.green)
								Text("connected").font(.callout)
							}
						}
						HStack {
							Image(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill")
								.font(.callout)
								.symbolRenderingMode(.hierarchical)
								.foregroundColor(node.isOnline ? .green : .orange)
							LastHeardText(lastHeard: node.lastHeard)
								.font(.callout)
						}
						HStack {
							let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
							Image(systemName: role?.systemName ?? "figure")
								.font(.callout)
								.symbolRenderingMode(.hierarchical)
							Text("Role: \(role?.name ?? "unknown".localized)")
								.font(.callout)
						}
						if node.positions?.count ?? 0 > 0 && connectedNode != node.num {
							HStack {
								let lastPostion = node.positions!.reversed()[0] as! PositionEntity
								if #available(iOS 17.0, macOS 14.0, *) {
									if let currentLocation = LocationsHandler.shared.locationsArray.last {
										let myCoord = CLLocation(latitude:  currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude)
										if lastPostion.nodeCoordinate != nil && myCoord.coordinate.longitude != LocationsHandler.DefaultLocation.longitude && myCoord.coordinate.latitude != LocationsHandler.DefaultLocation.latitude {
											let nodeCoord = CLLocation(latitude: lastPostion.nodeCoordinate!.latitude, longitude: lastPostion.nodeCoordinate!.longitude)
											let metersAway = nodeCoord.distance(from: myCoord)
											Image(systemName: "lines.measurement.horizontal")
												.font(.callout)
												.symbolRenderingMode(.hierarchical)
											DistanceText(meters: metersAway).font(.callout)
										}
									}
								} else {
									
									let myCoord = CLLocation(latitude: LocationHelper.currentLocation.latitude, longitude: LocationHelper.currentLocation.longitude)
									if lastPostion.nodeCoordinate != nil && myCoord.coordinate.longitude != LocationHelper.DefaultLocation.longitude && myCoord.coordinate.latitude != LocationHelper.DefaultLocation.latitude {
										let nodeCoord = CLLocation(latitude: lastPostion.nodeCoordinate!.latitude, longitude: lastPostion.nodeCoordinate!.longitude)
										let metersAway = nodeCoord.distance(from: myCoord)
										Image(systemName: "lines.measurement.horizontal")
											.font(.callout)
											.symbolRenderingMode(.hierarchical)
										DistanceText(meters: metersAway).font(.callout)
									}
								}
							}
						}
						HStack {
							if node.channel > 0 {
								Image(systemName: "fibrechannel")
									.font(.callout)
									.symbolRenderingMode(.hierarchical)
								Text("Channel: \(node.channel)")
									.foregroundColor(.gray)
									.font(.caption)
							}
							if node.viaMqtt && connectedNode != node.num {
								Image(systemName: "network")
									.symbolRenderingMode(.hierarchical)
									.font(.callout)
								Text("Via MQTT")
									.foregroundColor(.gray)
									.font(.caption)
							}
						}
						if !connected {
							HStack {
								let preset = ModemPresets(rawValue: Int(modemPreset))
								LoRaSignalStrengthMeter(snr: node.snr, rssi: node.rssi, preset: preset ?? ModemPresets.longFast, compact: true)
									.padding(.top, 2)
							}
						}
						HStack {
							BatteryLevelCompact(node: node, font: .caption, iconFont: .callout, color: .accentColor)

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
						.padding(.top, 3)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
			}
		}
		.padding([.top, .bottom])
	}
}
