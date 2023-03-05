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

@available(iOS 16.2, *)
struct WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
		
        ActivityConfiguration(for: MeshActivityAttributes.self) { context in
			LiveActivityView(nodeName: context.attributes.name, channelUtilization: context.state.channelUtilization, airtime: context.state.airtime, batteryLevel: context.state.batteryLevel, timerRange: context.state.timerRange)
				.widgetURL(URL(string: "meshtastic://node/\(context.attributes.name)"))

        } dynamicIsland: { context in
            DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					NodeInfoView(nodeName: context.attributes.name, timerRange: context.state.timerRange, channelUtilization: context.state.channelUtilization, airtime: context.state.airtime, batteryLevel: context.state.batteryLevel)
						.tint(Color("LightIndigo"))
						.padding(.top)
				}
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
				DynamicIslandExpandedRegion(.trailing, priority: 1) {
					HStack(alignment: .lastTextBaseline) {
						
						Spacer()
						TimerView(timerRange: context.state.timerRange)
							.tint(Color("LightIndigo"))
					}
					.padding(.top)
					
				}
				
            } compactLeading: {
				Image("logo-black")
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
				Image("logo-black")
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

@available(iOS 16.2, *)
struct WidgetsLiveActivity_Previews: PreviewProvider {
	static let attributes = MeshActivityAttributes(nodeNum: 123456789, name: "Meshtastic 8E6G")
	static let state = MeshActivityAttributes.ContentState(
		timerRange: Date.now...Date(timeIntervalSinceNow: 3600),  connected: true, channelUtilization: 25.84, airtime: 10.01, batteryLevel: 39)

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

@available(iOS 16.2, *)
struct LiveActivityView: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.isLuminanceReduced) var isLuminanceReduced
	
	var nodeName: String
	//var connected: Bool
	var channelUtilization: Float
	var airtime: Float
	var batteryLevel: UInt32
	var timerRange: ClosedRange<Date>
	
	var body: some View {
		HStack {
			Image(colorScheme == .light ? "logo-black" : "logo-white")
				.clipShape(ContainerRelativeShape())
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
			NodeInfoView(nodeName: nodeName, timerRange: timerRange, channelUtilization: channelUtilization, airtime: airtime, batteryLevel: batteryLevel)
			Spacer()
			TimerView(timerRange: timerRange)
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
	
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(nodeName)
				.font(.title3)
				.fontWeight(.semibold)
				.foregroundStyle(.tint)
				.fixedSize()
			Text("\(String(format: "Ch. Util: %.2f", channelUtilization))%")
				.font(.subheadline)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
				.fixedSize()
			Text("\(String(format: "Airtime: %.2f", airtime))%")
				.font(.subheadline)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
				.fixedSize()
			if batteryLevel < 101 {
				Text("Battery Level: \(batteryLevel > 0 ? String(batteryLevel) : "< 1")%")
					.font(.subheadline)
					.fontWeight(.medium)
					.foregroundStyle(.secondary)
					.opacity(isLuminanceReduced ? 0.5 : 1.0)
					.fixedSize()
			} else {
				Text("Plugged In")
					.font(.subheadline)
					.fontWeight(.medium)
					.foregroundStyle(.secondary)
					.opacity(isLuminanceReduced ? 0.5 : 1.0)
					.fixedSize()
			}
			Text(Date().formatted())
				.font(.subheadline)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
				.fixedSize()
		}
	}
}

struct TimerView: View {
	@Environment(\.isLuminanceReduced) var isLuminanceReduced
	
	var timerRange: ClosedRange<Date>
	
	var body: some View {
		VStack(alignment: .center) {
			Text("NEXT")
				.font(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
				.fixedSize()
			Text("UPDATE")
				.font(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
				.opacity(isLuminanceReduced ? 0.5 : 1.0)
				.fixedSize()
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
