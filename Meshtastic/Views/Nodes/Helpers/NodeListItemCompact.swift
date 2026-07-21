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

	private func accessibilityDescription(_ summary: NodeListRowSummary, cachedLocationData: (nodeLocation: CLLocation, myLocation: CLLocation)?) -> String {
		var desc = ""
		// The device shortName is never overridden by a local display name, so it's safe to branch
		// on it directly here; only the longName fallback needs the display-name-aware variant.
		if let shortName = summary.shortName, !shortName.isEmpty {
			desc = shortName.formatNodeNameForVoiceOver()
		} else if !summary.displayLongName.isEmpty {
			desc = summary.displayLongName
		} else {
			desc = "Unknown".localized + " " + "Node".localized
		}
		if isDirectlyConnected {
			desc += ", currently connected"
		}
		if summary.favorite {
			desc += ", favorite"
		}
		if let status = summary.statusMessage {
			desc += ", status: " + status
		}
		if let lastHeard = summary.lastHeard {
			let relative = Self.relativeDateFormatter.localizedString(for: lastHeard, relativeTo: Date())
			desc += ", last heard " + relative
		}
		if summary.isOnline {
			desc += ", online"
		} else {
			desc += ", offline"
		}
		if let roleName = summary.role?.name {
			desc += ", role: \(roleName)"
		}
		if summary.hopsAway > 0 {
			desc += ", \(summary.hopsAway) hops away"
		}
		if let battery = summary.batteryLevel {
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
		if summary.snr != 0 && !summary.viaMqtt {
			let signalStrength: BLESignalStrength
			if summary.snr < -10 {
				signalStrength = .weak
			} else if summary.snr < 5 {
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
		// Mirror the visual "Signed node" shield (rendered below) so VoiceOver announces it in the
		// compact list too — affirmative only, never for unsigned nodes.
		if summary.hasXeddsaSigned {
			desc += ", " + "Signed node".localized
		}
		return desc
	}

		@Bindable var node: NodeInfoEntity
		// Memoized value-type snapshot; rendered from instead of re-reading the live @Model on every
		// body re-evaluation, so a retained row can't fault on a deleted/zombie node. See NodeListItem.
		@State private var rowSummary: NodeListRowSummary?
		var isDirectlyConnected: Bool
		var connectedNode: Int64
	var modemPreset: ModemPresets = ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast

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
	
	private func lineNums(hasXeddsaSigned: Bool) -> Int {
		var lines = 1
		if shouldShowRole || shouldShowLocation || shouldShowTelemetry || shouldShowChannel || shouldShowHops || shouldShowSignal {
			lines += 1
		}

		if shouldShowLastHeard {
			lines += 1
		}

		// The signed-node ("Signed node") row renders on its own line whenever the node is signed,
		// so reserve space for it too — otherwise the avatar circle is sized too short for signed
		// nodes, most visibly when last-heard / telemetry rows are disabled.
		if hasXeddsaSigned {
			lines += 1
		}

		// Note: the status row's contribution is added by the caller via the resolved
		// `statusMessage` value, so `node.statusMessageDisplay` is evaluated only once.
		return lines
	}

	var body: some View {
		// Render from the cached value-type snapshot whenever we have one — that path never touches
		// the live @Model, so a row retained past the node's deletion (bulk deletes leave zombies
		// that `isDeleted` doesn't flag) can't fault. Only the first appearance reads the live node,
		// and only while it's still valid. See NodeListItem for the full explanation.
		if let rowSummary {
			rowContent(rowSummary)
		} else if node.modelContext != nil && !node.isDeleted {
			let summary = NodeListRowSummary(
				node: node,
				includeDeviceMetrics: shouldShowPower || shouldShowTelemetry,
				includePosition: shouldShowTelemetry || (shouldShowLocation && connectedNode != node.num),
				includeLogAvailability: shouldShowTelemetry
			)
			rowContent(summary)
				.onAppear { rowSummary = summary }
		} else {
			EmptyView()
		}
	}

	@ViewBuilder private func rowContent(_ summary: NodeListRowSummary) -> some View {
		// Resolve the status once per render; reused for the row, circle sizing, and a11y.
		let statusMessage = summary.statusMessage
		let circleSize = max(minCircle, min(maxCircle, baseUnit * CGFloat(lineNums(hasXeddsaSigned: summary.hasXeddsaSigned) + (statusMessage != nil ? 1 : 0))))
		let cachedBatteryLevel = (shouldShowPower || shouldShowTelemetry) ? summary.batteryLevel : nil
		let needsLatestPosition = shouldShowTelemetry || (shouldShowLocation && connectedNode != summary.num)
		let cachedLatestNodeCoordinate = needsLatestPosition ? summary.latestNodeCoordinate : nil
		let cachedLocationData = (shouldShowLocation && connectedNode != summary.num) ? locationData(for: cachedLatestNodeCoordinate) : nil
		let cachedHasPositions = shouldShowTelemetry ? summary.hasPosition : false
		let cachedHasDeviceMetrics = shouldShowTelemetry && summary.hasDeviceMetrics
		let cachedHasEnvironmentMetrics = shouldShowTelemetry ? summary.hasEnvironmentMetrics : false
		let cachedHasDetectionSensorMetrics = shouldShowTelemetry ? summary.hasDetectionSensorMetrics : false
		let cachedHasTraceRoutes = shouldShowTelemetry ? summary.hasTraceRoutes : false
		// Plain VStack, not LazyVStack: a LazyVStack inside a List cell returns inconsistent
		// self-sized heights and trips UICollectionViewCompositionalLayout's recursive
		// layout-loop trap on iOS 18+/26. See NodeListItem for the full explanation.
		VStack(alignment: .leading) {
			HStack {
				// First Column
				VStack(alignment: .center) {
					CircleText(text: summary.shortName ?? "?", color: Color(UIColor(hex: UInt32(summary.num))), circleSize: circleSize)
						.padding(.trailing, 5)
					if shouldShowPower, let batteryLevel = cachedBatteryLevel {
						BatteryCompact(batteryLevel: batteryLevel, font: .caption2, iconFont: .caption, color: .accentColor)
							.padding(.trailing, 5)
					}
				}
				// End First Column
				// Second Column
				VStack(alignment: .leading, spacing: rowSpacing) {
					HStack(alignment: .firstTextBaseline) {
						let (image, color) = summary.keyStatus
						IconAndText(systemName: image,
									imageColor: color,
									text: summary.displayLongName.addingVariationSelectors,
									textColor: .primary)
						if summary.favorite {
							Spacer()
							Image(systemName: "star.fill")
								.symbolRenderingMode(.multicolor)
						}
					}
					// Signed node = XEdDSA-signed NodeInfo broadcast → identity verified by the radio.
					// Affirmative only; never shown for unsigned nodes. Mirrors the Node Detail row.
					if summary.hasXeddsaSigned {
						IconAndText(systemName: "checkmark.shield.fill",
									imageColor: .green,
									text: "Signed node".localized)
					}
					// User-authored status broadcast by the node, directly beneath the name.
					// Single-line clamp keeps the compact row dense; omitted when empty.
					// Untrusted free text: rendered verbatim as plain text only.
					if let statusMessage {
						NodeCardStatusRow(
							status: statusMessage,
							iconWidth: nil,
							iconFont: .caption,
							textFont: .caption,
							lineLimit: 1
						)
						.padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0))
					}
					if shouldShowLastHeard && summary.lastHeard?.timeIntervalSince1970 ?? 0 > 0 && summary.lastHeard! < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {

						let lastHeardText = lastHeardIsRelative ?
						summary.lastHeard?.formatted(Date.RelativeFormatStyle()) :
						summary.lastHeard?.formatted()

						IconAndText(
							systemName: summary.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
							imageColor: summary.isOnline ? .green : .orange,
							text: lastHeardText ?? "Unknown Age".localized
						)
					}
					// Distance, bearing, hops, signal, role, telemetry row
					HStack(alignment: .center, spacing: 6) {
						if shouldShowLocation && connectedNode != summary.num {
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
						if shouldShowHops && summary.hopsAway > 0 {
							Divider().frame(height: 15)
							DefaultIconCompact(systemName: "\(summary.hopsAway).square")
						}
						if shouldShowSignal && summary.hopsAway == 0 && summary.snr != 0 && !summary.viaMqtt {
							Divider().frame(height: 15)
							let signalTier = getLoRaSignalStrength(snr: summary.snr, rssi: summary.rssi, preset: modemPreset)
							DefaultIconCompact(
								systemName: signalTier == .none ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right",
								variableValue: signalTier == .none ? nil : Double(signalTier.rawValue) / Double(LoRaSignalStrength.good.rawValue)
							)
								.foregroundColor(getSnrColor(snr: summary.snr, preset: modemPreset))
								.accessibilityLabel(
									String(localized: "Signal \(signalTier.description)", comment: "VoiceOver: LoRa signal quality of this directly-heard node")
								)
						}
						if shouldShowChannel && summary.channel > 0 {
							Divider().frame(height: 15)
							DefaultIconCompact(systemName: "\(summary.channel).circle.fill")
						}
						// Device Role
						if shouldShowRole {
							Divider().frame(height: 15)
							DefaultIconCompact(systemName: summary.role?.systemName ?? "figure")
							if summary.unmessagable {
								DefaultIconCompact(systemName: "iphone.slash")
							}
							if summary.isStoreForwardRouter {
								DefaultIconCompact(systemName: "envelope.arrow.triangle.branch")
							}
							if summary.viaMqtt && connectedNode != summary.num {
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
			// Gate the identity on liveness too: `.task(id:)` reads `node.lastHeard` during body
			// construction, which would fault on an invalidated model before the body's guard runs.
			.task(id: (node.modelContext != nil && !node.isDeleted) ? node.lastHeard : nil) {
				// Refresh the snapshot when the node changes, but only while it is still live.
				guard node.modelContext != nil && !node.isDeleted else { return }
				rowSummary = NodeListRowSummary(
					node: node,
					includeDeviceMetrics: shouldShowPower || shouldShowTelemetry,
					includePosition: needsLatestPosition,
					includeLogAvailability: shouldShowTelemetry
				)
			}
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(accessibilityDescription(summary, cachedLocationData: cachedLocationData))
	}
}

struct DefaultIconCompact: View {
	let systemName: String
	/// Optional 0...1 fill for symbols that support SF Symbols variable color (e.g. the
	/// radiowaves signal icon), so tiers are distinguishable by rendered shape, not color alone.
	var variableValue: Double?

	var body: some View {
		Image(systemName: systemName, variableValue: variableValue)
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
