//
//  NodeListItem.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//

import SwiftUI
import CoreLocation
import Foundation

struct NodeListRowSummary {
	// Snapshot the position and device metrics as plain value types at construction
	// time rather than vending live PositionEntity/TelemetryEntity objects. SwiftData
	// fatally traps (SIGTRAP in _SD_get_faulting_backingdata_tsd) if a deleted @Model's
	// persisted property is read, and both position rows and telemetry history are
	// pruned constantly underneath the list (telemetry via shouldPruneTelemetryHistory,
	// nullify relationship — so the captured metrics row can be deleted while the node
	// stays live). A view body holding either live object can crash mid-render; value-
	// type snapshots can never fault.
	let batteryLevel: Int32?
	let hasDeviceMetrics: Bool
	let hasPosition: Bool
	let latestNodeCoordinate: CLLocationCoordinate2D?
	let hasEnvironmentMetrics: Bool
	let hasDetectionSensorMetrics: Bool
	let hasTraceRoutes: Bool

	@MainActor init(
		node: NodeInfoEntity,
		includeDeviceMetrics: Bool = true,
		includePosition: Bool = true,
		includeLogAvailability: Bool = true
	) {
		let latestDeviceMetrics = includeDeviceMetrics ? node.latestDeviceMetrics : nil
		batteryLevel = latestDeviceMetrics?.batteryLevel
		hasDeviceMetrics = latestDeviceMetrics != nil
		let latestPosition = includePosition ? node.latestPosition : nil
		hasPosition = latestPosition != nil
		latestNodeCoordinate = latestPosition?.nodeCoordinate
		hasEnvironmentMetrics = includeLogAvailability ? node.hasEnvironmentMetrics : false
		hasDetectionSensorMetrics = includeLogAvailability ? node.hasDetectionSensorMetrics : false
		hasTraceRoutes = includeLogAvailability ? node.hasTraceRoutes : false
	}
}

struct NodeListItem: View {

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

	private func accessibilityDescription(batteryLevel: Int32?, cachedLocationData: (nodeLocation: CLLocation, myLocation: CLLocation)?, status: String?) -> String {
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
		if let status {
			desc += ", status: " + status
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
		if let battery = batteryLevel {
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
		// Mirror the visual "Signed node" trust signal (see the shield row below) so VoiceOver
		// announces it too — affirmative only, never for unsigned nodes.
		if node.hasXeddsaSigned {
			desc += ", " + "Signed node".localized
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
		let cachedBatteryLevel = rowSummary?.batteryLevel
		let cachedLocationData = connectedNode == node.num ? nil : locationData(for: rowSummary?.latestNodeCoordinate)
		let cachedHasPositions = rowSummary?.hasPosition ?? false
		let cachedHasDeviceMetrics = rowSummary?.hasDeviceMetrics ?? false
		let cachedHasEnvironmentMetrics = rowSummary?.hasEnvironmentMetrics ?? false
		let cachedHasDetectionSensorMetrics = rowSummary?.hasDetectionSensorMetrics ?? false
		let cachedHasTraceRoutes = rowSummary?.hasTraceRoutes ?? false
		let cachedHasLogs = cachedHasPositions || cachedHasEnvironmentMetrics || cachedHasDetectionSensorMetrics || cachedHasTraceRoutes
		// Resolve the status once per render and reuse it for the row + accessibility label,
		// rather than re-traversing the relationship for each read.
		let statusMessage = node.statusMessageDisplay
		// A plain VStack — NOT LazyVStack. A LazyVStack reports inconsistent self-sized
		// heights when measured inside a List cell (it sizes lazily from a scroll viewport),
		// which sends UICollectionViewCompositionalLayout into a recursive layout loop and
		// traps on iOS 18+/26 (_UICollectionViewFeedbackLoopDebugger). The laziness was also
		// pointless here — it wrapped a single HStack.
		VStack(alignment: .leading) {
			HStack {
				VStack(alignment: .center) {
					CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 70)
						.padding(.trailing, 5)
					if let batteryLevel = cachedBatteryLevel {
						BatteryCompact(batteryLevel: batteryLevel, font: .caption, iconFont: .callout, color: .accentColor)
							.padding(.trailing, 5)
					}
				}
				VStack(alignment: .leading) {
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
					// Signed node = XEdDSA-signed NodeInfo broadcast → identity verified by the radio.
					// Affirmative only; never shown for unsigned nodes. Mirrors the Node Detail row.
					if node.hasXeddsaSigned {
						IconAndText(systemName: "checkmark.shield.fill",
									imageColor: .green,
									text: "Signed node".localized)
					}
					// User-authored status broadcast by the node — shown directly beneath the
					// name, clamped to 2 lines so it can never grow the card unbounded. Omitted
					// entirely when empty (no placeholder). Untrusted free text: plain only.
					if let statusMessage {
						NodeCardStatusRow(
							status: statusMessage,
							iconWidth: 30,
							textFont: UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption,
							lineLimit: 2
						)
					}
					if isDirectlyConnected {
						IconAndText(systemName: "antenna.radiowaves.left.and.right.circle.fill",
									imageColor: .green,
									text: "Connected".localized)
					}
					if node.lastHeard?.timeIntervalSince1970 ?? 0 > 0 && node.lastHeard! < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
						IconAndText(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
									imageColor: node.isOnline ? .green : .orange,
							text: node.lastHeard?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized)
					}
					let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
					IconAndText(systemName: role?.systemName ?? "figure",
								text: "Role: \(role?.name ?? "Unknown".localized)")
					if node.user?.unmessagable ?? false {
						IconAndText(systemName: "iphone.slash",
									renderingMode: .multicolor,
									text: "Unmonitored")
					}
					if node.isStoreForwardRouter {
						IconAndText(systemName: "envelope.arrow.triangle.branch",
									renderingMode: .multicolor,
									text: "Store & Forward".localized)
					}
					
					if connectedNode != node.num {
						HStack {
							if let (nodeCoord, myCoord) = cachedLocationData {
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
					if cachedHasLogs {
						HStack {
							IconAndText(systemName: "scroll", text: "Logs:")
							if cachedHasDeviceMetrics {
								DefaultIcon(systemName: "flipphone")
							}
							if cachedHasPositions {
								DefaultIcon(systemName: "mappin.and.ellipse")
							}
							if cachedHasEnvironmentMetrics {
								DefaultIcon(systemName: "cloud.sun.rain")
							}
							if cachedHasDetectionSensorMetrics {
								DefaultIcon(systemName: "sensor")
							}
							if cachedHasTraceRoutes {
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
								.padding(.top, cachedHasLogs ? 0 : 15)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(.top, 3)
		.padding(.bottom, 3)
		.task(id: node.lastHeard) {
			rowSummary = await MainActor.run {
				NodeListRowSummary(node: node)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityDescription(batteryLevel: cachedBatteryLevel, cachedLocationData: cachedLocationData, status: statusMessage))
	}
}

/// Single source of truth for the Status Message presentation so the Notes glyph, color,
/// and plain-text/clamp policy stay identical across every surface that shows a node's
/// status (the two list cards and node detail) — the design spec requires the *same* Notes
/// icon on every surface and client.
enum NodeStatusStyle {
	/// The Notes glyph that labels a node's status everywhere it appears.
	static let glyph = "note.text"
}

/// The user-authored status row shown directly beneath a node's name on the list cards
/// (`NodeListItem`, `NodeListItemCompact`). Renders the Notes glyph (decorative) plus the
/// status as verbatim, clamped, plain text — `Text(_: String)` never parses markdown, so
/// untrusted mesh text can't inject markup. Callers gate on `node.statusMessageDisplay`.
struct NodeCardStatusRow: View {
	let status: String
	/// Width of the leading icon column; pass the surrounding rows' column width (e.g. 30)
	/// to keep the glyph aligned with sibling metadata icons, or `nil` for natural width.
	var iconWidth: CGFloat?
	var iconFont: Font = .callout
	var textFont: Font
	var lineLimit: Int

	var body: some View {
		HStack(alignment: .top) {
			Image(systemName: NodeStatusStyle.glyph)
				.font(iconFont)
				.symbolRenderingMode(.hierarchical)
				.foregroundColor(.secondary)
				.frame(width: iconWidth)
				.accessibilityHidden(true)
			Text(status)
				.font(textFont)
				.foregroundColor(.primary)
				.lineLimit(lineLimit)
				.truncationMode(.tail)
				.allowsTightening(true)
		}
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
	List {
		NodeListItem(node: {
			let nodeInfo = NodeInfoEntity()
			let user = UserEntity()
			user.longName = "Test User"
			user.shortName = "TU"
			nodeInfo.user = user
			return nodeInfo
		}(), isDirectlyConnected: true, connectedNode: 0, modemPreset: .longFast)
	}
}
