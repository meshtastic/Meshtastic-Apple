//
//  NodeListItemCompact.swift
//  Meshtastic
//
//  Created by Chase Christiansen on 3/20/26.
//  Branched from NodeListItem.swift on 3/20/26.
//

import SwiftUI
import CoreLocation
import Foundation

struct NodeListItemCompact: View {
	
	private var accessibilityDescription: String {
		var desc = ""
		if let shortName = node.user?.shortName {
			desc = shortName.formatNodeNameForVoiceOver()
		} else if let longName = node.user?.longName {
			desc = longName
		} else {
			desc = "Unknown".localized + " " + "Node".localized
		}
		if isDirectlyConnected {
			desc += ", currently connected"
		}
		if node.favorite {
			desc += ", favorite"
		}
		if node.lastHeard != nil {
			let formatter = RelativeDateTimeFormatter()
			formatter.unitsStyle = .full
			let relative = formatter.localizedString(for: node.lastHeard!, relativeTo: Date())
			desc += ", last heard " + relative
		}
		if node.isOnline {
			desc += ", online"
		} else {
			desc += ", offline"
		}
		let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
		if let roleName = role?.name {
			desc += ", role: \(roleName)"
		}
		if node.hopsAway > 0 {
			desc += ", \(node.hopsAway) hops away"
		}
		if let battery = node.latestDeviceMetrics?.batteryLevel {
			if battery > 100 {
				desc += ", " + "Plugged in".localized
			} else if battery == 100 {
				desc += ", " + "Charging".localized
			} else {
				desc += ", battery \(battery)%"
			}
		}
		if !isDirectlyConnected, let (lastPosition, myCoord) = locationData {
			let nodeCoord = CLLocation(latitude: lastPosition.nodeCoordinate!.latitude, longitude: lastPosition.nodeCoordinate!.longitude)
			let metersAway = nodeCoord.distance(from: myCoord)
			let distanceFormatter = LengthFormatter()
			distanceFormatter.unitStyle = .medium
			let formattedDistance = distanceFormatter.string(fromMeters: metersAway)
			desc += ", " + String(format: "%@: %@", "Distance".localized, formattedDistance)
			let trueBearing = getBearingBetweenTwoPoints(point1: myCoord, point2: nodeCoord)
			let heading = Measurement(value: trueBearing, unit: UnitAngle.degrees)
			let formattedHeading = heading.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0))))
			desc += ", " + "Heading".localized + " " + formattedHeading
		}
		if node.snr != 0 && !node.viaMqtt {
			let signalStrength: BLESignalStrength
			if node.snr < -10 {
				signalStrength = .weak
			} else if node.snr < 5 {
				signalStrength = .normal
			} else {
				signalStrength = .strong
			}
			let signalString: String
			switch signalStrength {
			case .weak:
				signalString = "Signal strength weak".localized
			case .normal:
				signalString = "Signal strength normal".localized
			case .strong:
				signalString = "Signal strength strong".localized
			}
			desc += ", " + signalString
		}
		return desc
	}
	
	@ObservedObject var node: NodeInfoEntity
	var isDirectlyConnected: Bool
	var connectedNode: Int64
	var modemPreset: ModemPresets = ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast
	
	var userKeyStatus: (String, Color) {
		var image = "lock.open.fill"
		var color = Color.yellow
		if node.user?.pkiEncrypted ?? false {
			if !(node.user?.keyMatch ?? false) {
				image = "key.slash"
				color = .red
			} else {
				image = "lock.fill"
				color = .green
			}
		}
		return (image, color)
	}
	
	var locationData: (PositionEntity, CLLocation)? {
		guard let lastPostion = node.positions?.lastObject as? PositionEntity else {
			return nil
		}
		guard let currentLocation = LocationsHandler.shared.locationsArray.last else {
			return nil
		}
		
		let myCoord = CLLocation(latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude)
		
		if lastPostion.nodeCoordinate != nil && myCoord.coordinate.longitude != LocationsHandler.DefaultLocation.longitude && myCoord.coordinate.latitude != LocationsHandler.DefaultLocation.latitude {
			return (lastPostion, myCoord)
		}
		return nil
	}
	
	var body: some View {
		LazyVStack(alignment: .leading) {
			HStack {
				VStack(alignment: .center) {
					CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 70)
						.padding(.trailing, 5)
				}
				VStack(alignment: .leading) {
					HStack {
						let (image, color) = userKeyStatus
						IconAndText(systemName: image,
									imageColor: color,
									text: node.user?.longName?.addingVariationSelectors ?? "Unknown".localized,
									textColor: .primary)
						Spacer()
						if node.latestDeviceMetrics != nil {
							BatteryCompact(batteryLevel: node.latestDeviceMetrics?.batteryLevel ?? 0, font: .caption, iconFont: .callout, color: .accentColor)
						}
						if node.favorite {
							Image(systemName: "star.fill")
								.symbolRenderingMode(.multicolor)
						}
					}
					if node.lastHeard?.timeIntervalSince1970 ?? 0 > 0 && node.lastHeard! < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
						IconAndText(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
									imageColor: node.isOnline ? .green : .orange,
									text: node.lastHeard?.formatted() ?? "Unknown Age".localized)
					}
					HStack {
						if node.channel > 0 {
							IconAndText(systemName: "\(node.channel).circle.fill", text: "Channel")
						}
					}
					// Display easy to differentiate information in a more compact list
					HStack(alignment: .bottom) {
						// Device Role
						let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
						DefaultIconCompact(systemName: role?.systemName ?? "figure")

						if node.user?.unmessagable ?? false {
							DefaultIconCompact(systemName: "iphone.slash")
						}
						if node.isStoreForwardRouter {
							DefaultIconCompact(systemName: "envelope.arrow.triangle.branch")
						}
						if node.viaMqtt && connectedNode != node.num {
							DefaultIconCompact(systemName: "dot.radiowaves.up.forward")
						}
						// Telemetry
						if node.hasPositions || node.hasEnvironmentMetrics || node.hasDetectionSensorMetrics || node.hasTraceRoutes {
							HStack(alignment: .bottom) {
								Divider().frame(height: 15)
								if node.hasDeviceMetrics {
									DefaultIconCompact(systemName: "flipphone")
								}
								if node.hasPositions {
									DefaultIconCompact(systemName: "mappin.and.ellipse")
								}
								if node.hasEnvironmentMetrics {
									DefaultIconCompact(systemName: "cloud.sun.rain")
								}
								if node.hasDetectionSensorMetrics {
									DefaultIconCompact(systemName: "sensor")
								}
								if node.hasTraceRoutes {
									DefaultIconCompact(systemName: "signpost.right.and.left")
								}
							}
						}
						// Location
						if node.positions?.count ?? 0 > 0 && connectedNode != node.num {
							Divider().frame(height: 15)
							HStack {
								if let (lastPostion, myCoord) = locationData {
									let nodeCoord = CLLocation(latitude: lastPostion.nodeCoordinate!.latitude, longitude: lastPostion.nodeCoordinate!.longitude)
									let metersAway = nodeCoord.distance(from: myCoord)

									DistanceText(meters: metersAway, isCompact: true)
										.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
										.foregroundColor(.gray)
									let trueBearing = getBearingBetweenTwoPoints(point1: myCoord, point2: nodeCoord)
									let headingDegrees = Measurement(value: trueBearing, unit: UnitAngle.degrees)
									Image(systemName: "location.north")
										.font(.callout)
										.symbolRenderingMode(.multicolor)
										.clipShape(Circle())
										.rotationEffect(Angle(degrees: headingDegrees.value))
								}
							}
						}

						Spacer()
						// Hops Away
						if node.hopsAway > 0 {
							DefaultIconCompact(systemName: "\(node.hopsAway).square")

						} else {
							if node.snr != 0 && !node.viaMqtt {
								DefaultIconCompact(systemName: "dot.radiowaves.left.and.right")
									.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
							}
						}

					}
					.padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0))
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityDescription)
	}
}

struct DefaultIconCompact: View {
	let systemName: String
	
	var body: some View {
		Image(systemName: systemName)
			.symbolRenderingMode(.hierarchical)
			.padding(.top, 2)
			.font(.callout)
	}
}

#Preview {
	List {
		NodeListItemCompact(node: {
			let context = PersistenceController.preview.container.viewContext
			let nodeInfo = NodeInfoEntity(context: context)
			let user = UserEntity(context: context)
			let telemetryEntity = TelemetryEntity(context: context)
			let positionEntity = PositionEntity(context: context)
			
			user.longName = "Hopscotch"
			user.shortName = "HS01"
			user.unmessagable = true
			user.pkiEncrypted = true
			user.role = 11
			nodeInfo.user = user
			
			telemetryEntity.batteryLevel = 100
			telemetryEntity.distance = 100
			nodeInfo.telemetries = [telemetryEntity]
			
			positionEntity.latitudeI = 30
			positionEntity.longitudeI = -90
			nodeInfo.positions = [positionEntity]

			nodeInfo.hopsAway = 0
			nodeInfo.snr = -17
			nodeInfo.viaMqtt = false
			nodeInfo.favorite = true
			nodeInfo.lastHeard = Date(timeIntervalSinceNow: 0)
			
			return nodeInfo
		}(), isDirectlyConnected: true, connectedNode: 0, modemPreset: .medFast)
		
		NodeListItemCompact(node: {
			let context = PersistenceController.preview.container.viewContext
			let nodeInfo = NodeInfoEntity(context: context)
			let storeForwardConfig = StoreForwardConfigEntity(context: context)
			let telemetryEntity = TelemetryEntity(context: context)
			let user = UserEntity(context: context)
			
			user.longName = "Brad!!"
			user.shortName = "B"
			user.unmessagable = false
			nodeInfo.user = user
			
			storeForwardConfig.enabled = true
			nodeInfo.storeForwardConfig = storeForwardConfig
			
			telemetryEntity.batteryLevel = 99
			telemetryEntity.distance = 100.0
			nodeInfo.telemetries = [telemetryEntity]

			nodeInfo.hopsAway = 7
			nodeInfo.lastHeard = Date(timeIntervalSinceNow: -3600)
			
			return nodeInfo
		}(), isDirectlyConnected: false, connectedNode: 1, modemPreset: .medFast)
		
		NodeListItemCompact(node: {
			let context = PersistenceController.preview.container.viewContext
			let nodeInfo = NodeInfoEntity(context: context)
			let user = UserEntity(context: context)
			
			user.longName = "MQTT Matt"
			user.shortName = "MQTM"
			user.unmessagable = false
			user.role = 3
			nodeInfo.user = user

			nodeInfo.hopsAway = 3
			nodeInfo.viaMqtt = true
			nodeInfo.lastHeard = Date(timeIntervalSinceNow: -98200)
			
			return nodeInfo
		}(), isDirectlyConnected: false, connectedNode: 1, modemPreset: .medFast)
		
		NodeListItemCompact(node: {
			let context = PersistenceController.preview.container.viewContext
			let nodeInfo = NodeInfoEntity(context: context)
			let user = UserEntity(context: context)
			let telemetryEntity = TelemetryEntity(context: context)
			
			user.longName = "Sneaky Little Roof Node 03"
			user.shortName = "SLN"
			user.unmessagable = false
			
			telemetryEntity.batteryLevel = 99
			telemetryEntity.distance = 100.0
			nodeInfo.telemetries = [telemetryEntity]

			nodeInfo.hopsAway = 1
			nodeInfo.lastHeard = Date(timeIntervalSinceNow: -300600)
			nodeInfo.favorite = true

			nodeInfo.user = user
			
			return nodeInfo
		}(), isDirectlyConnected: false, connectedNode: 1, modemPreset: .medFast)
	}
}
