//
//  WidgetsLiveActivity.swift
//  Widgets
//
//  Created by Garth Vander Houwen on 2/28/23.
//
#if os(iOS)
#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI

struct WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {

        ActivityConfiguration(for: MeshActivityAttributes.self) { context in
			LiveActivityView(nodeName: context.attributes.name,
							 uptimeSeconds: context.state.uptimeSeconds,
							 channelUtilization: context.state.channelUtilization,
							 airtime: context.state.airtime,
							 sentPackets: context.state.sentPackets,
							 receivedPackets: context.state.receivedPackets,
							 badReceivedPackets: context.state.badReceivedPackets,
							 dupeReceivedPackets: context.state.dupeReceivedPackets,
							 packetsSentRelay: context.state.packetsSentRelay,
							 packetsCanceledRelay: context.state.packetsCanceledRelay,
							 nodesOnline: context.state.nodesOnline,
							 totalNodes: context.state.totalNodes,
							 timerRange: context.state.timerRange)
				.widgetURL(URL(string: "meshtastic:///connect"))

        } dynamicIsland: { context in
            DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					Text(context.attributes.shortName)
						.font(.caption)
						.fontWeight(.semibold)
						.foregroundStyle(.primary)
						.fixedSize()
					Text("Sent: \(context.state.sentPackets)")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("ChUtil: \(context.state.channelUtilization?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)%")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Airtime: \(context.state.airtime?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)%")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Received: \(context.state.receivedPackets)")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
				}
				DynamicIslandExpandedRegion(.center) {
					TimerView(timerRange: context.state.timerRange)
						.tint(Color("LightIndigo"))
				}
				DynamicIslandExpandedRegion(.trailing, priority: 1) {
					if context.state.totalNodes > 0 {
						HStack(spacing: 3) {
							Image(systemName: "person.2.fill")
								.font(.caption2)
								.foregroundStyle(.secondary)
							Text("\(context.state.nodesOnline)/\(context.state.totalNodes)")
								.font(.caption)
								.fontWeight(.semibold)
								.foregroundStyle(.primary)
						}
						.fixedSize()
					}
					Text("Bad: \(context.state.badReceivedPackets)")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Dupe: \(context.state.dupeReceivedPackets)")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Relayed: \(context.state.packetsSentRelay)")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Rly Cancel: \(context.state.packetsCanceledRelay)")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
				}
				DynamicIslandExpandedRegion(.bottom) {
					HStack(spacing: 4) {
						if let uptime = context.state.uptimeSeconds, uptime > 0 {
							Text("UPTIME:")
								.font(.caption2)
								.foregroundStyle(.tint)
							Text(uptime >= 3600 ? "\(uptime / 3600)h \((uptime % 3600) / 60)m" : "\((uptime % 3600) / 60)m")
								.font(.caption2)
								.fontWeight(.medium)
								.foregroundStyle(.tint)
							Text("•")
								.font(.caption2)
								.foregroundStyle(.tint)
						}
						Text("UPDATED:")
							.font(.caption2)
							.foregroundStyle(.tint)
						Text("\(Date().formatted(date: .omitted, time: .shortened))")
							.font(.caption2)
							.fontWeight(.medium)
							.foregroundStyle(.tint)
					}
				}

            } compactLeading: {
				HStack(spacing: 2) {
					Image(systemName: "person.2.fill")
						.font(.system(size: 9))
						.foregroundStyle(.green)
					if context.state.totalNodes > 0 {
						Text("\(context.state.nodesOnline)")
							.font(.caption2)
							.fontWeight(.semibold)
							.foregroundStyle(.primary)
					}
				}
				.fixedSize()
            } compactTrailing: {
				Text("\(context.state.channelUtilization?.formatted(.number.precision(.fractionLength(1))) ?? "--")%")
					.font(.caption2)
					.fontWeight(.medium)
					.foregroundStyle(.primary)
					.fixedSize()
            } minimal: {
				ZStack {
					Image(systemName: "person.2.fill")
						.font(.system(size: 10))
						.foregroundStyle(.green)
					if context.state.totalNodes > 0 {
						Text("\(context.state.nodesOnline)")
							.font(.system(size: 7, weight: .bold))
							.foregroundStyle(.white)
							.offset(y: 6)
					}
				}
            }
			.contentMargins(.leading, 16, for: .expanded)
			.contentMargins(.trailing, 16, for: .expanded)
			.contentMargins(.all, 6, for: .compactLeading)
			.contentMargins(.all, 6, for: .compactTrailing)
			.contentMargins(.all, 6, for: .minimal)
			.widgetURL(URL(string: "meshtastic:///connect"))
        }
    }
}

struct WidgetsLiveActivity_Previews: PreviewProvider {
	static let attributes = MeshActivityAttributes(nodeNum: 123456789, name: "RAK Compact Rotary Handset Gray 8E6G", shortName: "8E6G")
	static let state = MeshActivityAttributes.ContentState(uptimeSeconds: 600, channelUtilization: 1.2, airtime: 3.5, sentPackets: 12587, receivedPackets: 12555, badReceivedPackets: 800, dupeReceivedPackets: 100, packetsSentRelay: 250, packetsCanceledRelay: 372, nodesOnline: 99, totalNodes: 100, timerRange: Date.now...Date(timeIntervalSinceNow: 300))

    static var previews: some View {
        attributes
            .previewContext(state, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Compact")
		attributes
			.previewContext(state, viewKind: .dynamicIsland(.minimal))
			.previewDisplayName("Minimal")
        attributes
            .previewContext(state, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Expanded")
		attributes
			.previewContext(state, viewKind: .content)
			.previewDisplayName("Notification")
    }
}
struct LiveActivityView: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.isLuminanceReduced) var isLuminanceReduced

	var nodeName: String
	var uptimeSeconds: UInt32?
	var channelUtilization: Float?
	var airtime: Float?
	var sentPackets: UInt32
	var receivedPackets: UInt32
	var badReceivedPackets: UInt32
	var dupeReceivedPackets: UInt32
	var packetsSentRelay: UInt32
	var packetsCanceledRelay: UInt32
	var nodesOnline: UInt32
	var totalNodes: UInt32
	var timerRange: ClosedRange<Date>

	var body: some View {
		let errorRate = receivedPackets > 0
			? (Double(badReceivedPackets) / Double(receivedPackets)) * 100
			: 0.0
		let now = Date()

		VStack(alignment: .leading, spacing: 4) {
			// Header row: logo + node name + nodes online
			HStack(spacing: 6) {
				Image("m-logo-white")
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 24, height: 24)
					.clipShape(RoundedRectangle(cornerRadius: 6))
				Text(nodeName)
					.font(.callout)
					.fontWeight(.semibold)
					.foregroundStyle(.tint)
					.lineLimit(1)
				Spacer()
				if totalNodes > 0 {
					HStack(spacing: 3) {
						Image(systemName: "person.2.fill")
							.font(.caption2)
							.foregroundStyle(.secondary)
						Text("\(nodesOnline)/\(totalNodes)")
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
					.fixedSize()
				}
			}

			// Stats grid — two columns
			HStack(alignment: .top, spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					StatRow(label: "Ch. Utilization", value: "\(channelUtilization?.formatted(.number.precision(.fractionLength(1))) ?? "--")%")
					StatRow(label: "Airtime", value: "\(airtime?.formatted(.number.precision(.fractionLength(1))) ?? "--")%")
					StatRow(label: "Sent", value: "\(sentPackets)")
					StatRow(label: "Received", value: "\(receivedPackets)")
				}
				VStack(alignment: .leading, spacing: 2) {
					StatRow(label: "Error Rate", value: "\(errorRate.formatted(.number.precision(.fractionLength(1))))%")
					StatRow(label: "Relayed", value: "\(packetsSentRelay)")
					StatRow(label: "Relay Canceled", value: "\(packetsCanceledRelay)")
					StatRow(label: "Duplicate", value: "\(dupeReceivedPackets)")
				}
			}
			.fixedSize(horizontal: true, vertical: false)
			.opacity(isLuminanceReduced ? 0.8 : 1.0)

			// Footer: uptime + timer
			HStack {
				Spacer(minLength: 0)
				if let uptimeSeconds, uptimeSeconds > 0 {
					Text("Uptime:")
						.font(.caption2)
						.foregroundStyle(.secondary)
					Text(uptimeText(uptimeSeconds))
						.font(.caption2)
						.fontWeight(.medium)
						.foregroundStyle(.tint)
					Text("•")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				if timerRange.upperBound >= now {
					Text("Update in:")
						.font(.caption2)
						.foregroundStyle(.secondary)
					Text(timerInterval: timerRange, countsDown: true)
						.monospacedDigit()
						.font(.caption2)
						.fontWeight(.medium)
						.foregroundStyle(.tint)
				} else {
					Text("Not Connected")
						.font(.caption2)
						.fontWeight(.semibold)
						.foregroundStyle(.tint)
				}
				Spacer(minLength: 0)
			}
			.fixedSize(horizontal: false, vertical: true)
		}
		.tint(.primary)
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.activityBackgroundTint(colorScheme == .light ? Color("LiveActivityBackground") : Color("AccentColorDimmed"))
		.activitySystemActionForegroundColor(.primary)
	}

	private func uptimeText(_ seconds: UInt32) -> String {
		let hours = seconds / 3600
		let minutes = (seconds % 3600) / 60
		if hours > 0 {
			return "\(hours)h \(minutes)m"
		}
		return "\(minutes)m"
	}
}

struct StatRow: View {
	var label: String
	var value: String

	var body: some View {
		HStack(spacing: 4) {
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.caption2)
				.fontWeight(.medium)
				.foregroundStyle(.primary)
		}
		.fixedSize()
	}
}

struct TimerView: View {
	@Environment(\.isLuminanceReduced) var isLuminanceReduced

	var timerRange: ClosedRange<Date>

	var body: some View {
		VStack(alignment: .center, spacing: 2) {
			Text("UPDATE IN")
				.font(.caption2)
				.allowsTightening(true)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
			Text(timerInterval: timerRange, countsDown: true)
				.monospacedDigit()
				.multilineTextAlignment(.center)
				.frame(width: 60)
				.font(.caption)
				.fontWeight(.semibold)
				.foregroundStyle(.tint)
			Image(systemName: "timer")
				.symbolRenderingMode(.multicolor)
				.resizable()
				.foregroundStyle(.secondary)
				.frame(width: 20, height: 20)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
		}
	}
}

struct ExpandedTrailingView: View {
	var nodeName: String
	var connected: Bool
	var channelUtilization: Float
	var airtime: Float
	var batteryLevel: UInt32
	var timerInterval: ClosedRange<Date>

	var body: some View {
		HStack(alignment: .lastTextBaseline) {
			Spacer()
			TimerView(timerRange: timerInterval)
		}
		.tint(Color("LightIndigo"))
	}
}
#endif
#endif
