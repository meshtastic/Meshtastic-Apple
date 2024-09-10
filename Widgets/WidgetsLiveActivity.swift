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
							 nodesOnline: context.state.nodesOnline,
							 totalNodes: context.state.totalNodes,
							 timerRange: context.state.timerRange)
				.widgetURL(URL(string: "meshtastic:///bluetooth"))

        } dynamicIsland: { context in
            DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
						Spacer()
						Text("Mesh")
							.font(.callout)
							.fontWeight(.medium)
							.foregroundStyle(.primary)
							.padding(.bottom, 10)
							.fixedSize()
						Spacer()
					}
					if context.state.totalNodes >= 100 {
						Text("100+ online")
							.font(.caption)
							.foregroundStyle(.secondary)
							.fixedSize()
					} else {
						Text("\(context.state.nodesOnline) of \(context.state.totalNodes) online")
							.font(.caption)
							.foregroundStyle(.secondary)
							.fixedSize()
					}
					Text("\(String(format: "Ch. Util: %.2f", context.state.channelUtilization))%")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("\(String(format: "Airtime: %.2f", context.state.airtime))%")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
				}
				DynamicIslandExpandedRegion(.center) {
					TimerView(timerRange: context.state.timerRange)
						.tint(Color("LightIndigo"))
				}
				DynamicIslandExpandedRegion(.trailing, priority: 1) {
					HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
						Spacer()
						Text("Packets")
							.font(.callout)
							.fontWeight(.medium)
							.foregroundStyle(.primary)
							.padding(.bottom, 10)
							.fixedSize()
						Spacer()
					}
					Text("Sent: \(context.state.sentPackets)")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Received: \(context.state.receivedPackets)")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("Bad: \(context.state.badReceivedPackets)")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
				}
				DynamicIslandExpandedRegion(.bottom) {
					Text("Last Heard: \(Date().formatted())")
						.font(.caption)
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
	static let state = MeshActivityAttributes.ContentState(uptimeSeconds: 600, channelUtilization: 1.2, airtime: 3.5, sentPackets: 12587, receivedPackets: 12555, badReceivedPackets: 800, nodesOnline: 99, totalNodes: 100, timerRange: Date.now...Date(timeIntervalSinceNow: 300))

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
	var uptimeSeconds: UInt32
	var channelUtilization: Float
	var airtime: Float
	var sentPackets: UInt32
	var receivedPackets: UInt32
	var badReceivedPackets: UInt32
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
			NodeInfoView(isLuminanceReduced: _isLuminanceReduced, nodeName: nodeName, uptimeSeconds: uptimeSeconds, channelUtilization: channelUtilization, airtime: airtime, sentPackets: sentPackets, receivedPackets: receivedPackets, badReceivedPackets: badReceivedPackets, nodesOnline: nodesOnline, totalNodes: totalNodes, timerRange: timerRange)
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
	var uptimeSeconds: UInt32
	var channelUtilization: Float
	var airtime: Float
	var sentPackets: UInt32
	var receivedPackets: UInt32
	var badReceivedPackets: UInt32
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
			Text("\(String(format: "Ch. Util: %.2f", channelUtilization))% \(String(format: "Airtime: %.2f", airtime))%")
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
			Text("Bad: \(badReceivedPackets) \(String(format: "Error Rate: %.2f", errorRate))%")
				.font(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.8 : 1.0)
				.fixedSize()
			if totalNodes >= 100 {
				Text("\(String(format: "Connected: %d nodes online", nodesOnline))")
					.font(.caption)
					.fontWeight(.medium)
					.foregroundStyle(.secondary)
					.opacity(isLuminanceReduced ? 0.8 : 1.0)
					.fixedSize()
			} else {
				Text("\(String(format: "Connected: %d of %d nodes online", nodesOnline, totalNodes))")
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
