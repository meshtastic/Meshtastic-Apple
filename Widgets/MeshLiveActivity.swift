//
//  MeshLiveActivity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//
//  The Live Activity, in the mode the user picked: a mesh status glance or one
//  tracked node, on the Lock Screen, in the Dynamic Island, and (iOS 18) in the
//  small family the Apple Watch Smart Stack and CarPlay use. No buttons: taps
//  open the app on the matching screen.
//

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

struct MeshLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: MeshLiveActivityAttributes.self) { context in
			LiveActivityLockScreen(activity: LiveActivityValues(context))
				.activitySystemActionForegroundColor(.primary)
				.widgetURL(LiveActivityValues(context).url)
		} dynamicIsland: { context in
			let activity = LiveActivityValues(context)
			return DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					ExpandedLeading(activity: activity)
				}
				DynamicIslandExpandedRegion(.trailing) {
					ExpandedTrailing(activity: activity)
				}
				DynamicIslandExpandedRegion(.center) {
					ExpandedCenter(activity: activity)
				}
				DynamicIslandExpandedRegion(.bottom) {
					ExpandedBottom(activity: activity)
				}
			} compactLeading: {
				CompactLeading(activity: activity)
			} compactTrailing: {
				CompactTrailing(activity: activity)
			} minimal: {
				Minimal(activity: activity)
			}
			.keylineTint(LiveActivityValues.brand)
			.widgetURL(activity.url)
		}
		.smallFamilyWhereAvailable()
	}
}

private extension WidgetConfiguration {
	/// The Apple Watch Smart Stack and CarPlay use the small family (iOS 18).
	func smallFamilyWhereAvailable() -> some WidgetConfiguration {
		if #available(iOS 18.0, *) {
			return supplementalActivityFamilies([.small])
		} else {
			return self
		}
	}
}

// MARK: - Values

/// Everything the views read, with the stale and connection rules applied once.
struct LiveActivityValues {
	/// Meshtastic brand green.
	static let brand = Color(red: 0x67 / 255, green: 0xEA / 255, blue: 0x94 / 255)

	let attributes: MeshLiveActivityAttributes
	let state: MeshLiveActivityAttributes.ContentState
	let isStale: Bool

	init(_ context: ActivityViewContext<MeshLiveActivityAttributes>) {
		attributes = context.attributes
		state = context.state
		isStale = context.isStale
	}

	var isConnected: Bool { state.connection == .connected }
	/// Readings shown dimmed: the radio isn't connected, or nothing new arrived
	/// before the stale date.
	var isDimmed: Bool { isStale || !isConnected }

	var trackedNum: Int64? { attributes.mode.trackedNodeNum }

	var url: URL? {
		if let trackedNum {
			return URL(string: "meshtastic:///nodes?nodenum=\(trackedNum)")
		}
		return URL(string: "meshtastic:///connect")
	}

	var radioSeed: UInt32 { UInt32(truncatingIfNeeded: attributes.radioNum) }
	var nodeSeed: UInt32 { UInt32(truncatingIfNeeded: trackedNum ?? 0) }
	var nodeShortName: String { attributes.nodeShortName ?? "?" }
	var nodeLongName: String { attributes.nodeLongName ?? attributes.nodeShortName ?? "?" }

	var nodesText: String {
		guard let online = state.nodesOnline else { return "—" }
		if let total = state.nodesTotal { return "\(online)/\(total)" }
		return "\(online)"
	}

	/// "Direct", "2 hops", plus the distance when known.
	var routeText: String? {
		var parts: [String] = []
		if let hops = state.hopsAway {
			parts.append(hops == 0 ? String(localized: "Direct") : String(localized: "\(hops) Hops"))
		}
		if let meters = state.distanceMeters {
			parts.append(Measurement(value: meters, unit: UnitLength.meters)
				.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1)))))
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}
}

// MARK: - Lock Screen

private struct LiveActivityLockScreen: View {
	let activity: LiveActivityValues

	var body: some View {
		if #available(iOS 18.0, *) {
			FamilyAwareLockScreen(activity: activity)
		} else {
			LockScreenContent(activity: activity)
		}
	}
}

/// The small family gets a two-line layout; everything else the full one.
@available(iOS 18.0, *)
private struct FamilyAwareLockScreen: View {
	@Environment(\.activityFamily) private var family
	let activity: LiveActivityValues

	var body: some View {
		switch family {
		case .small:
			SmallContent(activity: activity)
		default:
			LockScreenContent(activity: activity)
		}
	}
}

private struct LockScreenContent: View {
	let activity: LiveActivityValues

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if activity.trackedNum != nil {
				TrackedNodeBody(activity: activity)
			} else {
				MeshStatusBody(activity: activity)
			}
			LockScreenFooter(activity: activity)
		}
		.padding(14)
	}
}

private struct MeshStatusBody: View {
	let activity: LiveActivityValues

	var body: some View {
		HStack(spacing: 8) {
			MeshLogo(height: 14)
			Text(activity.attributes.radioLongName)
				.font(.headline)
				.lineLimit(2)
				.minimumScaleFactor(0.8)
			Spacer(minLength: 4)
			ConnectionDot(state: activity.state.connection)
		}
		HStack(alignment: .top, spacing: 0) {
			Reading(value: activity.nodesText, caption: "Nodes Online")
			Reading(value: activity.state.unreadCount.map { "\($0)" } ?? "—", caption: "Unread")
			Reading(value: batteryText(activity.state.radioBattery), caption: "Battery")
		}
		.opacity(activity.isDimmed ? 0.5 : 1)
	}
}

private struct TrackedNodeBody: View {
	let activity: LiveActivityValues

	var body: some View {
		HStack(alignment: .center, spacing: 12) {
			NodeChip(shortName: activity.nodeShortName, colorSeed: activity.nodeSeed, size: 44)
				.opacity(activity.isDimmed ? 0.5 : 1)
			VStack(alignment: .leading, spacing: 3) {
				Text(activity.nodeLongName)
					.font(.headline)
					.lineLimit(2)
					.minimumScaleFactor(0.8)
				HeardLine(activity: activity)
				if let routeText = activity.routeText {
					Text(routeText)
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
				}
			}
			Spacer(minLength: 4)
			VStack(alignment: .trailing, spacing: 4) {
				BatteryRow(level: activity.state.nodeBattery, font: .caption)
				SignalBars(rating: activity.state.signalRating)
			}
			.opacity(activity.isDimmed ? 0.5 : 1)
		}
	}
}

/// When the tracked node was last heard, aging by itself.
private struct HeardLine: View {
	let activity: LiveActivityValues

	var body: some View {
		Group {
			if let lastHeard = activity.state.lastHeard {
				Text("Heard \(lastHeard, style: .relative) ago")
			} else {
				Text("Not heard yet")
			}
		}
		.font(.caption)
		.foregroundStyle(activity.isStale ? Color.orange : .secondary)
		.fixedSize()
	}
}

private struct LockScreenFooter: View {
	let activity: LiveActivityValues

	var body: some View {
		ViewThatFits(in: .horizontal) {
			HStack(spacing: 4) {
				status
				Spacer(minLength: 4)
				until
			}
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 4) { status }
				until
			}
		}
		.font(.caption2)
		.foregroundStyle(.secondary)
	}

	@ViewBuilder
	private var status: some View {
		if activity.trackedNum != nil {
			MeshLogo(height: 10)
			Text("via \(activity.attributes.radioShortName)")
				.fixedSize()
		}
		if !activity.isConnected {
			Text(stateText(activity.state.connection))
				.fixedSize()
		} else if activity.trackedNum == nil {
			// The node counts are the main reading, and they're only as fresh
			// as the radio's last LocalStats.
			Text("Updated \(activity.state.statsAt ?? activity.state.updatedAt, style: .relative) ago")
				.fixedSize()
		}
	}

	private var until: some View {
		Text("Until \(activity.attributes.updatesEndAt, style: .time)")
			.fixedSize()
	}
}

/// One value over its caption, in an equal-width column.
private struct Reading: View {
	let value: String
	let caption: LocalizedStringKey

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			Text(value)
				.font(.title3.weight(.semibold))
				.monospacedDigit()
				.lineLimit(1)
				.minimumScaleFactor(0.7)
			Text(caption)
				.font(.caption2)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.7)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

// MARK: - Small family (Apple Watch Smart Stack, CarPlay)

private struct SmallContent: View {
	let activity: LiveActivityValues

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 6) {
				if activity.trackedNum != nil {
					NodeChip(shortName: activity.nodeShortName, colorSeed: activity.nodeSeed, size: 26)
					Text(activity.nodeLongName)
						.font(.caption.weight(.semibold))
						.lineLimit(1)
						.minimumScaleFactor(0.6)
				} else {
					MeshLogo(height: 12)
					Text(activity.attributes.radioShortName)
						.font(.caption.weight(.semibold))
						.lineLimit(1)
						.minimumScaleFactor(0.6)
				}
				Spacer(minLength: 2)
				ConnectionDot(state: activity.state.connection)
			}
			HStack(spacing: 8) {
				if activity.trackedNum != nil {
					if let lastHeard = activity.state.lastHeard {
						Text(lastHeard, style: .relative)
							.monospacedDigit()
					}
					Spacer(minLength: 2)
					BatteryRow(level: activity.state.nodeBattery, font: .caption2)
				} else {
					Label(activity.nodesText, systemImage: "person.2.fill")
					Spacer(minLength: 2)
					Label(activity.state.unreadCount.map { "\($0)" } ?? "—", systemImage: "message.fill")
				}
			}
			.font(.caption2)
			.lineLimit(1)
			.minimumScaleFactor(0.7)
			.opacity(activity.isDimmed ? 0.5 : 1)
		}
		.padding(10)
	}
}

// MARK: - Dynamic Island

private struct CompactLeading: View {
	let activity: LiveActivityValues

	var body: some View {
		if activity.trackedNum != nil {
			NodeChip(shortName: activity.nodeShortName, colorSeed: activity.nodeSeed, size: 22)
		} else {
			MeshLogo(height: 12)
				.environment(\.colorScheme, .dark)
		}
	}
}

private struct CompactTrailing: View {
	let activity: LiveActivityValues

	var body: some View {
		if !activity.isConnected {
			Image(systemName: "antenna.radiowaves.left.and.right.slash")
				.foregroundStyle(.secondary)
		} else if activity.trackedNum != nil {
			if let lastHeard = activity.state.lastHeard {
				// Counts up from the last time the node was heard.
				Text(lastHeard, style: .timer)
					.font(.caption2.weight(.semibold))
					.monospacedDigit()
					.minimumScaleFactor(0.6)
					.multilineTextAlignment(.trailing)
					.frame(maxWidth: 52)
					.foregroundStyle(activity.isStale ? Color.orange : LiveActivityValues.brand)
			} else {
				Text(verbatim: "—")
			}
		} else {
			HStack(spacing: 3) {
				Image(systemName: "person.2.fill")
				Text(activity.state.nodesOnline.map { "\($0)" } ?? "—")
					.monospacedDigit()
			}
			.foregroundStyle(LiveActivityValues.brand)
		}
	}
}

private struct Minimal: View {
	let activity: LiveActivityValues

	var body: some View {
		if activity.trackedNum != nil {
			NodeChip(shortName: activity.nodeShortName, colorSeed: activity.nodeSeed, size: 22)
		} else if activity.isConnected {
			Text(activity.state.nodesOnline.map { "\($0)" } ?? "—")
				.font(.caption2.weight(.bold))
				.monospacedDigit()
				.minimumScaleFactor(0.6)
				.foregroundStyle(LiveActivityValues.brand)
		} else {
			Image(systemName: "antenna.radiowaves.left.and.right.slash")
				.foregroundStyle(.secondary)
		}
	}
}

private struct ExpandedLeading: View {
	let activity: LiveActivityValues

	var body: some View {
		Group {
			if activity.trackedNum != nil {
				NodeChip(shortName: activity.nodeShortName, colorSeed: activity.nodeSeed, size: 38)
					.opacity(activity.isDimmed ? 0.5 : 1)
			} else {
				NodeChip(shortName: activity.attributes.radioShortName, colorSeed: activity.radioSeed, size: 38)
			}
		}
		.padding(.leading, 4)
		.frame(maxHeight: .infinity, alignment: .center)
	}
}

private struct ExpandedTrailing: View {
	let activity: LiveActivityValues

	// Beside the camera there's room for an icon, not a reading; the battery
	// is in the bottom row.
	var body: some View {
		Group {
			if activity.trackedNum != nil {
				SignalBars(rating: activity.state.signalRating)
					.font(.title3)
					.opacity(activity.isDimmed ? 0.5 : 1)
			}
		}
		.padding(.trailing, 4)
		.frame(maxHeight: .infinity, alignment: .center)
	}
}

/// The Meshtastic mark and the name under the camera, with the connection
/// state when it isn't connected.
private struct ExpandedCenter: View {
	let activity: LiveActivityValues

	var body: some View {
		VStack(spacing: 2) {
			HStack(spacing: 6) {
				MeshLogo(height: 11)
					.environment(\.colorScheme, .dark)
				Text(activity.trackedNum != nil ? activity.nodeLongName : activity.attributes.radioLongName)
					.font(.headline)
					.lineLimit(2)
					.minimumScaleFactor(0.7)
					.multilineTextAlignment(.center)
			}
			if !activity.isConnected {
				Text(stateText(activity.state.connection))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}
}

/// The readings and when updates stop, on one row when it fits and two when
/// it doesn't; nothing is ever cut off. Inset so the island's rounded corners
/// never clip it.
private struct ExpandedBottom: View {
	let activity: LiveActivityValues

	var body: some View {
		ViewThatFits(in: .horizontal) {
			HStack(spacing: 12) {
				readings
				Spacer(minLength: 6)
				untilText
			}
			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 12) {
					readings
				}
				HStack {
					Spacer(minLength: 0)
					untilText
				}
			}
		}
		.padding(.horizontal, 10)
		.padding(.bottom, 4)
	}

	@ViewBuilder
	private var readings: some View {
		if activity.trackedNum != nil {
			HeardLine(activity: activity)
				.fixedSize()
			if let routeText = activity.routeText {
				Text(routeText)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize()
			}
			BatteryRow(level: activity.state.nodeBattery, font: .footnote)
				.fixedSize()
				.opacity(activity.isDimmed ? 0.5 : 1)
		} else {
			Group {
				Label(activity.nodesText, systemImage: "person.2.fill")
					.foregroundStyle(LiveActivityValues.brand)
				Label(activity.state.unreadCount.map { $0.formatted() } ?? "—", systemImage: "message.fill")
				BatteryRow(level: activity.state.radioBattery, font: .footnote.weight(.semibold))
			}
			.font(.footnote.weight(.semibold))
			.monospacedDigit()
			.fixedSize()
			.opacity(activity.isDimmed ? 0.5 : 1)
		}
	}

	private var untilText: some View {
		Text("Until \(activity.attributes.updatesEndAt, style: .time)")
			.font(.caption2)
			.foregroundStyle(.secondary)
			.fixedSize()
	}
}

// MARK: - Helpers

private func batteryText(_ level: Int32?) -> String {
	guard let level else { return "—" }
	return level > 100 ? String(localized: "Powered") : "\(level)%"
}
#endif
