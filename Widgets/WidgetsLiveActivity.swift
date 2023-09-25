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
			LiveActivityView(nodeName: context.attributes.name, channelUtilization: context.state.channelUtilization, airtime: context.state.airtime, batteryLevel: context.state.batteryLevel, nodes: 17, nodesOnline: 7, timerRange: context.state.timerRange)
				.widgetURL(URL(string: "meshtastic://node/\(context.attributes.name)"))

        } dynamicIsland: { context in
            DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					Text("Network")
						.font(.headline)
						.fontWeight(.bold)
						.foregroundStyle(.secondary)
						.fixedSize()
						.padding(.top, 10)
					Text("\(String(format: "Ch. Util: %.2f", context.state.channelUtilization))%")
						.font(.headline)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.fixedSize()
					Text("\(String(format: "Airtime: %.2f", context.state.airtime))%")
						.font(.headline)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.fixedSize()
					Spacer()
				}
				DynamicIslandExpandedRegion(.center) {
					VStack(alignment: .center, spacing: 0) {
						BatteryIcon(batteryLevel: Int32(context.state.batteryLevel), font: .title, color: .accentColor)
						if context.state.batteryLevel == 0 {
							Text("< 1%")
								.font(.title3)
								.foregroundColor(.gray)
								.fixedSize()
						} else if context.state.batteryLevel < 101 {
							Text(String(context.state.batteryLevel) + "%")
								.font(.title3)
								.foregroundColor(.gray)
								.fixedSize()
						} else {
							Text("PWD")
								.font(.title3)
								.foregroundColor(.gray)
						}
					}
				}
				DynamicIslandExpandedRegion(.trailing, priority: 1) {
					TimerView(timerRange: context.state.timerRange)
						.tint(Color("LightIndigo"))

				}
				DynamicIslandExpandedRegion(.bottom) {
					Text(context.attributes.name)
						.font(context.attributes.name.count > 14 ? .callout : .title3)
						.fontWeight(.semibold)
						.foregroundStyle(.tint)
					Text("Last Heard: \(Date().formatted())")
						.font(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.fixedSize()
				}

            } compactLeading: {
				Image("m-logo-black")
					.resizable()
					.frame(width: 30.0)
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
			.widgetURL(URL(string: "meshtastic://node/\(context.attributes.name)"))
        }
    }
}

struct WidgetsLiveActivity_Previews: PreviewProvider {
	static let attributes = MeshActivityAttributes(nodeNum: 123456789, name: "RAK Compact Rotary Handset Gray 8E6G")
	static let state = MeshActivityAttributes.ContentState(
		timerRange: Date.now...Date(timeIntervalSinceNow: 60), connected: true, channelUtilization: 25.84, airtime: 10.01, batteryLevel: 39, nodes: 17, nodesOnline: 9)

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
	// var connected: Bool
	var channelUtilization: Float
	var airtime: Float
	var batteryLevel: UInt32
	var nodes: Int
	var nodesOnline: Int
	var timerRange: ClosedRange<Date>

	var body: some View {
		HStack {
			Image(colorScheme == .light ? "m-logo-black" : "m-logo-white")
				.resizable()
				.clipShape(ContainerRelativeShape())
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
				.aspectRatio(contentMode: .fit)
				.frame(width: 65)
			Spacer()
			NodeInfoView(nodeName: nodeName, timerRange: timerRange, channelUtilization: channelUtilization, airtime: airtime, batteryLevel: batteryLevel, nodes: nodes, nodesOnline: nodesOnline)
			Spacer()
			VStack {
				BatteryIcon(batteryLevel: Int32(batteryLevel), font: .title, color: .secondary)
				if batteryLevel == 0 {
					Text("< 1%")
						.font(.headline)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.opacity(isLuminanceReduced ? 0.8 : 1.0)
						.fixedSize()
				} else if batteryLevel < 101 {
					Text(String(batteryLevel) + "%")
						.font(.headline)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.opacity(isLuminanceReduced ? 0.8 : 1.0)
						.fixedSize()
				} else {
					Text("Plugged In")
						.font(.headline)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.opacity(isLuminanceReduced ? 0.8 : 1.0)
						.fixedSize()
				}
			}
		}
		.tint(.primary)
		.padding([.leading, .top, .bottom])
		.padding(.trailing, 32)
		.activityBackgroundTint(colorScheme == .light ? Color("LiveActivityBackground") : Color("AccentColorDimmed"))
		.activitySystemActionForegroundColor(.primary)
	}
}

struct NodeInfoView: View {
	@Environment(\.isLuminanceReduced) var isLuminanceReduced

	var nodeName: String
	var timerRange: ClosedRange<Date>
	var channelUtilization: Float
	var airtime: Float
	var batteryLevel: UInt32
	var nodes: Int
	var nodesOnline: Int

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(nodeName)
				.font(nodeName.count > 14 ? .callout : .title3)
				.fontWeight(.semibold)
				.foregroundStyle(.tint)
			Text("\(String(format: "Ch. Util: %.2f", channelUtilization))%")
				.font(.headline)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.8 : 1.0)
				.fixedSize()
			Text("\(String(format: "Airtime: %.2f", airtime))%")
				.font(.headline)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.8 : 1.0)
				.fixedSize()
//			Text("\(String(format: "Connected: %d of %d online", nodesOnline, nodes))")
//				.font(.callout)
//				.fontWeight(.medium)
//				.foregroundStyle(.secondary)
//				.opacity(isLuminanceReduced ? 0.8 : 1.0)
//				.fixedSize()
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
			Text("NEXT UPDATE")
				.font(.caption)
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
				.resizable()
				.foregroundStyle(.secondary)
				.frame(width: 30, height: 30)
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
