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
	
	@AppStorage(NodeListPreferences.shouldShowLocation.rawValue) private var shouldShowLocation = true
	@AppStorage(NodeListPreferences.shouldShowPower.rawValue) private var shouldShowPower = true
	@AppStorage(NodeListPreferences.shouldShowTelemetry.rawValue) private var shouldShowTelemetry = true
	@AppStorage(NodeListPreferences.shouldShowLastHeard.rawValue) private var shouldShowLastHeard = true
	@AppStorage(NodeListPreferences.lastHeardIsRelative.rawValue) private var lastHeardIsRelative = false
	@AppStorage(NodeListPreferences.shouldShowRole.rawValue) private var shouldShowRole = true
	@AppStorage(NodeListPreferences.shouldShowChannel.rawValue) private var shouldShowChannel = true
	@AppStorage(NodeListPreferences.shouldShowHops.rawValue) private var shouldShowHops = true
	@AppStorage(NodeListPreferences.shouldShowSignal.rawValue) private var shouldShowSignal = true

	@ScaledMetric(relativeTo: .body) private var baseUnit: CGFloat = 24
	@ScaledMetric(relativeTo: .body) private var minCircle: CGFloat = 36
	@ScaledMetric(relativeTo: .body) private var maxCircle: CGFloat = 50
	@ScaledMetric(relativeTo: .caption) private var rowSpacing: CGFloat = 2

	private static let relativeDateFormatter: RelativeDateTimeFormatter = {
		let f = RelativeDateTimeFormatter()
		f.unitsStyle = .full
		return f
	}()

	private static let distanceFormatter: LengthFormatter = {
		let f = LengthFormatter()
		f.unitStyle = .medium
		return f
	}()

	private func accessibilityDescription(cachedMetrics: TelemetryEntity?, cachedLocationData: (nodeLocation: CLLocation, myLocation: CLLocation)?) -> String {
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
		if let lastHeard = node.lastHeard {
			let relative = Self.relativeDateFormatter.localizedString(for: lastHeard, relativeTo: Date())
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
		if let battery = cachedMetrics?.batteryLevel {
			if battery > 100 {
				desc += ", " + "Plugged in".localized
			} else if battery == 100 {
				desc += ", " + "Charging".localized
			} else {
				desc += ", battery \(battery)%"
			}
		}
		if !isDirectlyConnected, let (nodeCoord, myCoord) = cachedLocationData {
			let metersAway = nodeCoord.distance(from: myCoord)
			let formattedDistance = Self.distanceFormatter.string(fromMeters: metersAway)
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

		@Bindable var node: NodeInfoEntity
		@State private var rowSummary: NodeListRowSummary?
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
	
	func locationData(for nodeCoordinate: CLLocationCoordinate2D?) -> (nodeLocation: CLLocation, myLocation: CLLocation)? {
		guard let nodeCoordinate else {
			return nil
		}
		guard let currentLocation = LocationsHandler.shared.locationsArray.last else {
			return nil
		}

		let myCoord = CLLocation(latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude)

		if myCoord.coordinate.longitude != LocationsHandler.DefaultLocation.longitude && myCoord.coordinate.latitude != LocationsHandler.DefaultLocation.latitude {
			return (CLLocation(latitude: nodeCoordinate.latitude, longitude: nodeCoordinate.longitude), myCoord)
		}
		return nil
	}
	
	var lineNums: Int {
		var lines = 1
		if shouldShowRole || shouldShowLocation || shouldShowTelemetry || shouldShowChannel || shouldShowHops || shouldShowSignal {
			lines += 1
		}
		
		if shouldShowLastHeard {
			lines += 1
		}
		
		return lines
	}
	
	var body: some View {
		// A List row view can be retained and re-evaluate its body after the underlying
		// node row has been deleted (nodes/positions are pruned constantly). Reading any
		// persisted property of a deleted @Model fatally traps in SwiftData, so bail to an
		// empty row when the node is no longer live — the List drops it on its next rebuild.
		// Mirrors the modelContext guard already used in NodeList/NodeDetail.
		if node.modelContext != nil && !node.isDeleted {
			rowContent
		} else {
			EmptyView()
		}
	}

	@ViewBuilder private var rowContent: some View {
		let circleSize = max(minCircle, min(maxCircle, baseUnit * CGFloat(lineNums)))
		let cachedMetrics = (shouldShowPower || shouldShowTelemetry) ? rowSummary?.latestDeviceMetrics : nil
		let needsLatestPosition = shouldShowTelemetry || (shouldShowLocation && connectedNode != node.num)
		let cachedLatestNodeCoordinate = needsLatestPosition ? rowSummary?.latestNodeCoordinate : nil
		let cachedLocationData = (shouldShowLocation && connectedNode != node.num) ? locationData(for: cachedLatestNodeCoordinate) : nil
		let cachedHasPositions = shouldShowTelemetry ? (rowSummary?.hasPosition ?? false) : false
		let cachedHasDeviceMetrics = shouldShowTelemetry && cachedMetrics != nil
		let cachedHasEnvironmentMetrics = shouldShowTelemetry ? rowSummary?.hasEnvironmentMetrics ?? false : false
		let cachedHasDetectionSensorMetrics = shouldShowTelemetry ? rowSummary?.hasDetectionSensorMetrics ?? false : false
		let cachedHasTraceRoutes = shouldShowTelemetry ? rowSummary?.hasTraceRoutes ?? false : false
		// Plain VStack, not LazyVStack: a LazyVStack inside a List cell returns inconsistent
		// self-sized heights and trips UICollectionViewCompositionalLayout's recursive
		// layout-loop trap on iOS 18+/26. See NodeListItem for the full explanation.
		VStack(alignment: .leading) {
			HStack {
				// First Column
				VStack(alignment: .center) {
					CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: circleSize)
						.padding(.trailing, 5)
					if shouldShowPower, let batteryLevel = cachedMetrics?.batteryLevel {
						BatteryCompact(batteryLevel: batteryLevel, font: .caption2, iconFont: .caption, color: .accentColor)
							.padding(.trailing, 5)
					}
				}
				// End First Column
				// Second Column
				VStack(alignment: .leading, spacing: rowSpacing) {
					HStack(alignment: .firstTextBaseline) {
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
					if shouldShowLastHeard && node.lastHeard?.timeIntervalSince1970 ?? 0 > 0 && node.lastHeard! < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
						
						let lastHeardText = lastHeardIsRelative ?
						node.lastHeard?.formatted(Date.RelativeFormatStyle()) :
						node.lastHeard?.formatted()
						
						IconAndText(
							systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
							imageColor: node.isOnline ? .green : .orange,
							text: lastHeardText ?? "Unknown Age".localized
						)
					}
					// Distance, bearing, hops, signal, role, telemetry row
					HStack(alignment: .center, spacing: 6) {
						if shouldShowLocation && connectedNode != node.num {
							if let (nodeCoord, myCoord) = cachedLocationData {
								let metersAway = nodeCoord.distance(from: myCoord)
								DistanceText(meters: metersAway, isCompact: true)
									.font(.callout)
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
						if shouldShowHops && node.hopsAway > 0 {
							Divider().frame(height: 15)
							DefaultIconCompact(systemName: "\(node.hopsAway).square")
						}
						if shouldShowSignal && node.hopsAway == 0 && node.snr != 0 && !node.viaMqtt {
							Divider().frame(height: 15)
							DefaultIconCompact(systemName: "dot.radiowaves.left.and.right")
								.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
						}
						if shouldShowChannel && node.channel > 0 {
							Divider().frame(height: 15)
							DefaultIconCompact(systemName: "\(node.channel).circle.fill")
						}
						// Device Role
						if shouldShowRole {
							Divider().frame(height: 15)
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
						}
						// Telemetry
						if shouldShowTelemetry && (cachedHasPositions || cachedHasEnvironmentMetrics || cachedHasDetectionSensorMetrics || cachedHasTraceRoutes) {
							Divider().frame(height: 15)
							if cachedHasDeviceMetrics {
								DefaultIconCompact(systemName: "flipphone")
							}
							if cachedHasPositions {
								DefaultIconCompact(systemName: "mappin.and.ellipse")
							}
							if cachedHasEnvironmentMetrics {
								DefaultIconCompact(systemName: "cloud.sun.rain")
							}
							if cachedHasDetectionSensorMetrics {
								DefaultIconCompact(systemName: "sensor")
							}
							if cachedHasTraceRoutes {
								DefaultIconCompact(systemName: "signpost.right.and.left")
							}
						}
					}
					.padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0))
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				// End Second Column
			}
		}
			.padding(.top, 2)
			.padding(.bottom, 2)
			.task(id: node.lastHeard) {
				rowSummary = await MainActor.run {
					NodeListRowSummary(
						node: node,
						includeDeviceMetrics: shouldShowPower || shouldShowTelemetry,
						includePosition: needsLatestPosition,
						includeLogAvailability: shouldShowTelemetry
					)
				}
			}
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(accessibilityDescription(cachedMetrics: cachedMetrics, cachedLocationData: cachedLocationData))
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
			let nodeInfo = NodeInfoEntity()
			let user = UserEntity()
			let telemetryEntity = TelemetryEntity()
			let positionEntity = PositionEntity()
			
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
			let nodeInfo = NodeInfoEntity()
			let storeForwardConfig = StoreForwardConfigEntity()
			let telemetryEntity = TelemetryEntity()
			let user = UserEntity()
			
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
			let nodeInfo = NodeInfoEntity()
			let user = UserEntity()
			
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
			let nodeInfo = NodeInfoEntity()
			let user = UserEntity()
			let telemetryEntity = TelemetryEntity()
			
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
