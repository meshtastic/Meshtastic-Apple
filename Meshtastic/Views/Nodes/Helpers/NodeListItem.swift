//
//  NodeListItem.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//

import SwiftUI
import CoreLocation
import Foundation

/// A complete, value-type snapshot of everything a node-list row renders, captured from the live
/// `NodeInfoEntity` (and its `user` relationship) while it is valid.
///
/// SwiftData fatally traps (SIGTRAP in `_SD_get_faulting_backingdata_tsd`) when a persisted
/// property — especially a relationship like `NodeInfoEntity.user` — is read on a model whose
/// backing row has been removed. Bulk deletes (`clearStaleNodes`, `clearDatabase`'s
/// `delete(model:)`) invalidate in-memory instances *without* flipping `isDeleted`, so a retained
/// List row that re-evaluates its body before the List drops it reads a zombie and crashes — the
/// top crash on 2.7.15 (NodeListItem/NodeListItemCompact, ~48% of crashes).
///
/// The row memoizes one of these snapshots in `@State` (see `NodeListItem.body`) and renders from
/// it, so a re-evaluation after the model dies never touches the live object. Value types can't
/// fault.
struct NodeListRowSummary {
	// Identity / name
	let num: Int64
	let shortName: String?
	let displayLongName: String
	let role: DeviceRoles?
	let pkiEncrypted: Bool
	let keyMatch: Bool
	let unmessagable: Bool

	// Node scalars
	let favorite: Bool
	let hasXeddsaSigned: Bool
	let statusMessage: String?
	let lastHeard: Date?
	let isOnline: Bool
	let hopsAway: Int32
	let snr: Float
	let rssi: Int32
	let channel: Int32
	let viaMqtt: Bool
	let isStoreForwardRouter: Bool

	// Snapshotted metrics / position / log availability (never vend live PositionEntity/
	// TelemetryEntity — those rows are pruned constantly underneath the list and would fault too).
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
		num = node.num
		let user = node.user
		shortName = user?.shortName
		displayLongName = user?.displayLongName ?? "Unknown".localized
		role = DeviceRoles(rawValue: Int(user?.role ?? 0))
		pkiEncrypted = user?.pkiEncrypted ?? false
		keyMatch = user?.keyMatch ?? false
		unmessagable = user?.unmessagable ?? false

		favorite = node.favorite
		hasXeddsaSigned = node.hasXeddsaSigned
		statusMessage = node.statusMessageDisplay
		lastHeard = node.lastHeard
		isOnline = node.isOnline
		hopsAway = node.hopsAway
		snr = node.snr
		rssi = node.rssi
		channel = node.channel
		viaMqtt = node.viaMqtt
		isStoreForwardRouter = node.isStoreForwardRouter

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

	/// The lock/key glyph and color for the node's PKI state — derived from the snapshot so the row
	/// never re-reads `node.user` at render time.
	var keyStatus: (image: String, color: Color) {
		if pkiEncrypted {
			return keyMatch ? ("lock.fill", .green) : ("key.slash", .red)
		}
		return ("lock.open.fill", .yellow)
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
		// Mirror the visual "Signed node" trust signal (see the shield row below) so VoiceOver
		// announces it too — affirmative only, never for unsigned nodes.
		if summary.hasXeddsaSigned {
			desc += ", " + "Signed node".localized
		}
		return desc
	}

	@Bindable var node: NodeInfoEntity
	/// The memoized value-type snapshot the row renders from. Captured while the node is live and
	/// never re-derived from the live model during a plain re-evaluation, so a retained row can't
	/// fault on a zombie @Model. Refreshed (guarded) when the node's `lastHeard` changes.
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

	var body: some View {
		// Render from the cached snapshot whenever we have one — this path never touches the live
		// @Model, so a row retained past the node's deletion (nodes/positions are pruned constantly;
		// bulk deletes leave zombies that `isDeleted` doesn't flag) can't fault. Only the first
		// appearance reads the live node, and only while it's still valid.
		if let rowSummary {
			rowContent(rowSummary)
		} else if node.modelContext != nil && !node.isDeleted {
			let summary = NodeListRowSummary(node: node)
			rowContent(summary)
				.onAppear { rowSummary = summary }
		} else {
			EmptyView()
		}
	}

	@ViewBuilder private func rowContent(_ summary: NodeListRowSummary) -> some View {
		let cachedBatteryLevel = summary.batteryLevel
		let cachedLocationData = connectedNode == summary.num ? nil : locationData(for: summary.latestNodeCoordinate)
		let cachedHasPositions = summary.hasPosition
		let cachedHasDeviceMetrics = summary.hasDeviceMetrics
		let cachedHasEnvironmentMetrics = summary.hasEnvironmentMetrics
		let cachedHasDetectionSensorMetrics = summary.hasDetectionSensorMetrics
		let cachedHasTraceRoutes = summary.hasTraceRoutes
		let cachedHasLogs = cachedHasPositions || cachedHasEnvironmentMetrics || cachedHasDetectionSensorMetrics || cachedHasTraceRoutes
		let statusMessage = summary.statusMessage
		// A plain VStack — NOT LazyVStack. A LazyVStack reports inconsistent self-sized
		// heights when measured inside a List cell (it sizes lazily from a scroll viewport),
		// which sends UICollectionViewCompositionalLayout into a recursive layout loop and
		// traps on iOS 18+/26 (_UICollectionViewFeedbackLoopDebugger). The laziness was also
		// pointless here — it wrapped a single HStack.
		VStack(alignment: .leading) {
			HStack {
				VStack(alignment: .center) {
					CircleText(text: summary.shortName ?? "?", color: Color(UIColor(hex: UInt32(summary.num))), circleSize: 70)
						.padding(.trailing, 5)
					if let batteryLevel = cachedBatteryLevel {
						BatteryCompact(batteryLevel: batteryLevel, font: .caption, iconFont: .callout, color: .accentColor)
							.padding(.trailing, 5)
					}
				}
				VStack(alignment: .leading) {
					HStack {
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
					if summary.lastHeard?.timeIntervalSince1970 ?? 0 > 0 && summary.lastHeard! < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
						IconAndText(systemName: summary.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
									imageColor: summary.isOnline ? .green : .orange,
							text: summary.lastHeard?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized)
					}
					IconAndText(systemName: summary.role?.systemName ?? "figure",
								text: "Role: \(summary.role?.name ?? "Unknown".localized)")
					if summary.unmessagable {
						IconAndText(systemName: "iphone.slash",
									renderingMode: .multicolor,
									text: "Unmonitored")
					}
					if summary.isStoreForwardRouter {
						IconAndText(systemName: "envelope.arrow.triangle.branch",
									renderingMode: .multicolor,
									text: "Store & Forward".localized)
					}

					if connectedNode != summary.num {
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
						if summary.channel > 0 {
							IconAndText(systemName: "\(summary.channel).circle.fill", text: "Channel")
						}

						if summary.viaMqtt && connectedNode != summary.num {
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
					if summary.hopsAway > 0 {
						HStack {
							IconAndText(systemName: "hare", text: "Hops Away:")
							Image(systemName: "\(summary.hopsAway).square")
								.font(.title2)
						}
					} else {
						if summary.snr != 0 && !summary.viaMqtt {
							LoRaSignalStrengthMeter(snr: summary.snr, rssi: summary.rssi, preset: modemPreset, compact: true)
								.padding(.top, cachedHasLogs ? 0 : 15)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(.top, 3)
		.padding(.bottom, 3)
		// Gate the identity on liveness too: `.task(id:)` reads `node.lastHeard` during body
		// construction, which would fault on an invalidated model before the body's guard runs.
		.task(id: (node.modelContext != nil && !node.isDeleted) ? node.lastHeard : nil) {
			// Refresh the snapshot when the node changes, but only while it is still live.
			guard node.modelContext != nil && !node.isDeleted else { return }
			rowSummary = NodeListRowSummary(node: node)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityDescription(summary, cachedLocationData: cachedLocationData))
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
