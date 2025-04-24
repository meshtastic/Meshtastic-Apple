//
//  WidgetsLiveActivity.swift
//  Widgets
//
//  Created by Garth Vander Houwen on 2/28/23.
//
#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI

struct WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {

        ActivityConfiguration(for: MeshActivityAttributes.self) { context in
			LiveActivityView(nodeName: context.attributes.name,
							 uptimeSeconds: 0, // context.attributes.uptimeSeconds,
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
				.widgetURL(URL(string: "meshtastic:///bluetooth"))

        } dynamicIsland: { context in
            DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					if context.state.totalNodes > 0 {
						Text("  \(context.state.nodesOnline) online")
							.font(.callout)
							.foregroundStyle(.secondary)
							.fixedSize()
					} else {
						Text("  ")
							.font(.callout)
							.foregroundStyle(.secondary)
							.fixedSize()
					}
					Text("Ch. Util: \(context.state.channelUtilization?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)%")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Airtime: \(context.state.airtime?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)%")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Sent: \(context.state.sentPackets)")
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
					Spacer()
					Text("Bad: \(context.state.badReceivedPackets)")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Dupe: \(context.state.dupeReceivedPackets)")
					   .font(.caption)
					   .foregroundStyle(.secondary)
					   .fixedSize()
					Text("Relayed: \(context.state.packetsSentRelay)")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Relay Cancel: \(context.state.packetsCanceledRelay)")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
				}
				DynamicIslandExpandedRegion(.bottom) {
					Text("Last Heard: \(Date().formatted())")
						.font(.caption2)
						.fontWeight(.medium)
						.foregroundStyle(.tint)
						.fixedSize()
				}

            } compactLeading: {
				Image("m-logo-black")
					.resizable()
					.frame(width: 25)
					.padding(4)
					.background(.green.gradient, in: ContainerRelativeShape())
            } compactTrailing: {
				Text(timerInterval: context.state.timerRange, countsDown: true)
					.monospacedDigit()
					.foregroundColor(Color("LightIndigo"))
					.frame(width: 40)
            } minimal: {
				Image("m-logo-black")
					.resizable()
					.frame(width: 24.0)
					.padding(4)
					.background(.green.gradient, in: ContainerRelativeShape())
            }
			.contentMargins(.trailing, 32, for: .expanded)
			.contentMargins([.leading, .top, .bottom], 6, for: .compactLeading)
			.contentMargins(.all, 6, for: .minimal)
			.widgetURL(URL(string: "meshtastic:///bluetooth"))
        }
    }
}

struct WidgetsLiveActivity_Previews: PreviewProvider {
	static let attributes = MeshActivityAttributes(nodeNum: 123456789, name: "RAK Compact Rotary Handset Gray 8E6G")
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
		HStack {
			Spacer()
			Image(colorScheme == .light ? "m-logo-black" : "m-logo-white")
				.resizable()
				.clipShape(ContainerRelativeShape())
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
				.aspectRatio(contentMode: .fit)
				.frame(minWidth: 25, idealWidth: 45, maxWidth: 55)
			Spacer()
			NodeInfoView(isLuminanceReduced: _isLuminanceReduced, nodeName: nodeName, uptimeSeconds: uptimeSeconds, channelUtilization: channelUtilization, airtime: airtime, sentPackets: sentPackets, receivedPackets: receivedPackets, badReceivedPackets: badReceivedPackets,
				dupeReceivedPackets: dupeReceivedPackets, packetsSentRelay: packetsSentRelay, packetsCanceledRelay: packetsCanceledRelay, nodesOnline: nodesOnline, totalNodes: totalNodes, timerRange: timerRange)
			Spacer()
		}
		.tint(.primary)
		.padding([.leading, .top, .bottom])
		.padding(.trailing, 25)
		.activityBackgroundTint(colorScheme == .light ? Color("LiveActivityBackground") : Color("AccentColorDimmed"))
		.activitySystemActionForegroundColor(.primary)
	}
}

struct NodeInfoView: View {
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
		let errorRate = (Double(badReceivedPackets) / Double(receivedPackets)) * 100
		VStack(alignment: .leading, spacing: 0) {
			Text(nodeName)
				.font(nodeName.count > 14 ? .callout : .title3)
				.fontWeight(.semibold)
				.foregroundStyle(.tint)
			// Text("\(channelUtilization.map { String(format: "Ch. Util: %.2f", $0 ) } ?? "--")% \(airtime.map { String(format: "Airtime: %.2f", $0) } ?? "--")%")
			Text("Ch. Util: \(channelUtilization?.formatted(.number.precision(.fractionLength(2))) ?? Constants.nilValueIndicator)%")
				.font(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.8 : 1.0)
				.fixedSize()
			Text("Packets: Sent \(sentPackets) Rec. \(receivedPackets)")
				.font(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.8 : 1.0)
				.fixedSize()
			Text("Bad: \(badReceivedPackets) Error Rate: \(errorRate.formatted(.number.precision(.fractionLength(2))))%")
				.font(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.8 : 1.0)
				.fixedSize()
			if totalNodes >= 100 {
				Text("Connected: \(nodesOnline) nodes online")
					.font(.caption)
					.fontWeight(.medium)
					.foregroundStyle(.secondary)
					.opacity(isLuminanceReduced ? 0.8 : 1.0)
					.fixedSize()
			} else {
				Text("Connected: \(nodesOnline) of \(totalNodes) nodes online")
					.font(.caption)
					.fontWeight(.medium)
					.foregroundStyle(.secondary)
					.opacity(isLuminanceReduced ? 0.8 : 1.0)
					.fixedSize()
			}
			let now = Date()
			Text("Last Heard: \(now.formatted())")
				.font(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.8 : 1.0)
				.fixedSize()
			HStack {

				if timerRange.upperBound >= now {
					Text("Next Update:")
						.font(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.opacity(isLuminanceReduced ? 0.8 : 1.0)
						.fixedSize()
					Text(timerInterval: timerRange, countsDown: true)
						.monospacedDigit()
						.multilineTextAlignment(.leading)
						.font(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.tint)
				} else {
					Text("Not Connected")
						.multilineTextAlignment(.leading)
						.font(.caption)
						.fontWeight(.semibold)
						.foregroundStyle(.tint)
				}
			}
		}
	}
}

struct TimerView: View {
	@Environment(\.isLuminanceReduced) var isLuminanceReduced

	var timerRange: ClosedRange<Date>

	var body: some View {
		VStack(alignment: .center) {
			Text("UPDATE IN")
				.font(.caption2)
				.allowsTightening(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
			Text(timerInterval: timerRange, countsDown: true)
				.monospacedDigit()
				.multilineTextAlignment(.center)
				.frame(width: 80)
				.font(.callout)
				.fontWeight(.semibold)
				.foregroundStyle(.tint)
			Image(systemName: "timer")
				.symbolRenderingMode(.multicolor)
				.resizable()
				.foregroundStyle(.secondary)
				.frame(width: 30, height: 30)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
				.offset(y: -5)
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
