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

	var userKeyStatus: (String, Color) {
		var image = "lock.open.fill"
		var color = Color.yellow
		if node.user?.pkiEncrypted ?? false {
			if !(node.user?.keyMatch ?? false) {
				/// Public Key on the User and the Public Key on the Last Message don't match
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
		NavigationLink(value: node) {
			LazyVStack(alignment: .leading) {
				HStack {
					VStack(alignment: .center) {
						CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 70)
							.padding(.trailing, 5)
						if node.latestDeviceMetrics != nil {
							BatteryCompact(batteryLevel: node.latestDeviceMetrics?.batteryLevel ?? 0, font: .caption, iconFont: .callout, color: .accentColor)
								.padding(.trailing, 5)
						}
					}
					VStack(alignment: .leading) {
						HStack {
							let (image, color) = userKeyStatus
							IconAndText(systemName: image,
										imageColor: color,
										text: node.user?.longName?.addingVariationSelectors ?? "unknown".localized,
										textColor: .primary)
							if node.favorite {
								Spacer()
								Image(systemName: "star.fill")
									.symbolRenderingMode(.multicolor)
							}
						}
						if connected {
							IconAndText(systemName: "antenna.radiowaves.left.and.right.circle.fill",
										imageColor: .green,
										text: "connected".localized)
						}
						if node.lastHeard?.timeIntervalSince1970 ?? 0 > 0 && node.lastHeard! < Calendar.current.date(byAdding: .year, value: 1, to: Date())!{
							IconAndText(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
										imageColor: node.isOnline ? .green : .orange,
										text: node.lastHeard?.formatted() ?? "unknown.age".localized)
						}
						let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
						IconAndText(systemName: role?.systemName ?? "figure",
									text: "Role: \(role?.name ?? "unknown".localized)")
						if node.isStoreForwardRouter {
							IconAndText(systemName: "envelope.arrow.triangle.branch",
										renderingMode: .multicolor,
										text: "Store & Forward".localized)
						}

						if node.positions?.count ?? 0 > 0 && connectedNode != node.num {
							HStack {
								if let (lastPostion, myCoord) = locationData {
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
						HStack {
							if node.channel > 0 {
								IconAndText(systemName: "\(node.channel).circle.fill", text: "Channel")
							}

							if node.viaMqtt && connectedNode != node.num {
								IconAndText(systemName: "dot.radiowaves.up.forward",
											renderingMode: .multicolor,
											text: "MQTT")
							}
						}
						if node.hasPositions || node.hasEnvironmentMetrics || node.hasDetectionSensorMetrics || node.hasTraceRoutes {
							HStack {
								IconAndText(systemName: "scroll", text: "Logs:")
								if node.hasDeviceMetrics {
									DefaultIcon(systemName: "flipphone")
								}
								if node.hasPositions {
									DefaultIcon(systemName: "mappin.and.ellipse")
								}
								if node.hasEnvironmentMetrics {
									DefaultIcon(systemName: "cloud.sun.rain")
								}
								if node.hasDetectionSensorMetrics {
									DefaultIcon(systemName: "sensor")
								}
								if node.hasTraceRoutes {
									DefaultIcon(systemName: "signpost.right.and.left")
								}
							}
						}
						if node.hopsAway > 0 {
							HStack {
								IconAndText(systemName: "hare", text: "Hops Away:")
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

struct DefaultIcon: View {
	let systemName: String

	var body: some View {
		Image(systemName: systemName)
			.symbolRenderingMode(.hierarchical)
			.font(.callout)
	}
}

struct IconAndText: View {
	let systemName: String
	var imageColor: Color?
	var renderingMode: SymbolRenderingMode = .hierarchical
	let text: String
	var textColor: Color = .gray

	@ViewBuilder
	var image: some View {
		if let color = imageColor {
			Image(systemName: systemName)
				.foregroundColor(color)
		} else {
			Image(systemName: systemName)
		}
	}

	var body: some View {
		HStack {
			image
				.font(.callout)
				.symbolRenderingMode(renderingMode)
				.frame(width: 30)
			Text(text)
				.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
				.foregroundColor(textColor)
				.allowsTightening(true)
		}
	}
}

#Preview {
	VStack(alignment: .leading) {
		IconAndText(systemName: "antenna.radiowaves.left.and.right.circle.fill", text: "foo")
		IconAndText(systemName: "antenna.radiowaves.left.and.right.circle", text: "bar")
		NodeListItem(node: {
			let context = PersistenceController.preview.container.viewContext
			let nodeInfo = NodeInfoEntity(context: context)
			let user = UserEntity(context: context)
			user.longName = "Test User"
			user.shortName = "TU"
			nodeInfo.user = user
			return nodeInfo
		}(), connected: true, connectedNode: 0, modemPreset: .longFast)
	}
}
