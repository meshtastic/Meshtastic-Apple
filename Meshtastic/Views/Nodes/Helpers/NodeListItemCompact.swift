//
//  NodeListItem.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//

import SwiftUI
import CoreLocation
import Foundation

struct NodeListItemCompact: View {

    // Accessibility: Synthesized description for VoiceOver
    private var accessibilityDescription: String {
        var desc = ""
        if let shortName = node.user?.shortName {
            // Format the shortName using the String extension method
            desc = shortName.formatNodeNameForVoiceOver()
        } else if let longName = node.user?.longName {
            desc = longName
        } else {
			desc = "Unknown".localized + " " + "Node".localized
        }
        if connected {
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
            // Check for plugged in and charging states, same logic as in BatteryCompact and BatteryGauge
            if battery > 100 {
				desc += ", " + "Plugged in".localized
            } else if battery == 100 {
				desc += ", " + "Charging".localized
            } else {
                desc += ", battery \(battery)%"
            }
        }
        // Add distance and heading/bearing if available, but only for non-connected nodes
        if !connected, let (lastPosition, myCoord) = locationData {
            let nodeCoord = CLLocation(latitude: lastPosition.nodeCoordinate!.latitude, longitude: lastPosition.nodeCoordinate!.longitude)
            let metersAway = nodeCoord.distance(from: myCoord)
            // Distance information
            let distanceFormatter = LengthFormatter()
            distanceFormatter.unitStyle = .medium
            let formattedDistance = distanceFormatter.string(fromMeters: metersAway)
            // For VoiceOver, prepend 'Distance' (localized)
			desc += ", " + String(format: "%@: %@", "Distance".localized, formattedDistance)
            // Add bearing/heading information for VoiceOver
            let trueBearing = getBearingBetweenTwoPoints(point1: myCoord, point2: nodeCoord)
            let heading = Measurement(value: trueBearing, unit: UnitAngle.degrees)
            let formattedHeading = heading.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0))))
            // Using a direct format without requiring a new localization key
			desc += ", " + "Heading".localized + " " + formattedHeading
        }
        // Add signal strength if available
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
//					User Icon
					VStack(alignment: .center) {
						CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 50)
							.padding(.trailing, 5)
					}
//					User Info
					VStack(alignment: .leading) {
//						User name/encryption
						HStack {
							let (image, color) = userKeyStatus
							IconAndText(systemName: image,
										imageColor: color,
										text: node.user?.longName?.addingVariationSelectors ?? "Unknown".localized,
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
										text: "Connected".localized)
						}
						if node.lastHeard?.timeIntervalSince1970 ?? 0 > 0 && node.lastHeard! < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
							IconAndText(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
										imageColor: node.isOnline ? .green : .orange,
										text: node.lastHeard?.formatted() ?? "Unknown Age".localized)
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
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
				let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))

//					Compact Info Stack
				HStack(alignment: .center) {
					if node.latestDeviceMetrics != nil {
						BatteryCompact(batteryLevel: node.latestDeviceMetrics?.batteryLevel ?? 0, font: .caption, iconFont: .callout, color: .accentColor)
					}
					Spacer()
					//	Node Unmessagable Indicator
					if node.user?.unmessagable ?? false {
						Image(systemName: "iphone.slash")
					}
					//	Node Store/Forward Indicator
					if node.isStoreForwardRouter {
						Image(systemName: "envelope.arrow.triangle.branch")
					}
					//	Node Role Image
					Image(systemName: role?.systemName ?? "figure")
					//	Node Hops/Signal Indicator
					if node.hopsAway > 0 {
						Image(systemName: "\(node.hopsAway).square")
							.font(.title2)
							.scaledToFit()
					} else {
						Image(systemName: "dot.radiowaves.left.and.right")
							.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
					}
				}
			}
		}
		.padding(.top, 4)
		.padding(.bottom, 4)
        // Accessibility: Make the whole row a single element for VoiceOver
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}

#Preview {
	List {
		NodeListItemCompact(node: {
			let context = PersistenceController.preview.container.viewContext
			let nodeInfo = NodeInfoEntity(context: context)
			let user = UserEntity(context: context)
			user.longName = "Test User"
			user.shortName = "TU"
			user.unmessagable = true
			nodeInfo.favorite = true
			nodeInfo.channel = 2
			nodeInfo.num = 2
			nodeInfo.viaMqtt = true
			nodeInfo.user = user
			nodeInfo.lastHeard = Date.now
			return nodeInfo
		}(), connected: true, connectedNode: 0, modemPreset: .longFast)
		NodeListItemCompact(node: {
			let context = PersistenceController.preview.container.viewContext
			let nodeInfo = NodeInfoEntity(context: context)
			let user = UserEntity(context: context)
			user.longName = "Test User 2"
			user.shortName = "TU2"
			user.unmessagable = true
			nodeInfo.favorite = true
			nodeInfo.num = 2
			nodeInfo.user = user
			nodeInfo.lastHeard = Date.now - 8192
			nodeInfo.hopsAway = 5
			return nodeInfo
		}(), connected: false, connectedNode: 0, modemPreset: .longFast)
	}
}
