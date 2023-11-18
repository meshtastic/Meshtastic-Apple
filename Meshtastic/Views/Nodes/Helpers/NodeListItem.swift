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
						BatteryLevelCompact(node: node, font: .caption, iconFont: .callout, color: .accentColor)
					}
					VStack(alignment: .leading) {
						HStack {
							Text(node.user?.longName ?? "unknown".localized)
								.fontWeight(.medium)
								.font(.headline)
							if node.user?.vip ?? false {
								Spacer()
								Image(systemName: "star.fill")
									.foregroundColor(.secondary)
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
						if node.positions?.count ?? 0 > 0 && connectedNode != node.num {
							HStack {
								let lastPostion = node.positions!.reversed()[0] as! PositionEntity
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
						if node.channel > 0 {
							HStack {
								Image(systemName: "fibrechannel")
									.font(.callout)
									.symbolRenderingMode(.hierarchical)
								Text("Channel: \(node.channel)")
									.font(.callout)
							}
						}
						
						if !connected {
							HStack {
								let preset = ModemPresets(rawValue: Int(modemPreset))
								LoRaSignalStrengthMeter(snr: node.snr, rssi: node.rssi, preset: preset ?? ModemPresets.longFast, compact: true)
							}
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
			}
		}
		.padding([.top, .bottom])
	}
}
