////
////  MeshActivityWidget.swift
////  Meshtastic
////
////  Created by Garth Vander Houwen on 2/24/23.
////
//
///*
//See LICENSE folder for this sample’s licensing information.
//
//Abstract:
//Defines the live activity and dynamic island.
//*/
//
//import SwiftUI
//import WidgetKit
//
//
//struct MeshActivityWidget: Widget {
//	
//	var body: some WidgetConfiguration {
//		
//		ActivityConfiguration(for: MeshActivityAttributes.self) { context in
//			LiveActivityView(orderNumber: String(context.attributes.nodeNum), timerRange: context.state.timerRange)
//				.widgetURL(URL(string: "meshtastic://node/\(context.attributes.nodeNum)"))
//		} dynamicIsland: { context in
//			DynamicIsland {
//				DynamicIslandExpandedRegion(.leading) {
//					ExpandedLeadingView()
//				}
//
//				DynamicIslandExpandedRegion(.trailing, priority: 1) {
//					ExpandedTrailingView(orderNumber: String(context.attributes.nodeNum), timerInterval: context.state.timerRange)
//						.dynamicIsland(verticalPlacement: .belowIfTooWide)
//				}
//			} compactLeading: {
//				Image("IslandCompactIcon")
//					.padding(4)
//					.background(.indigo.gradient, in: ContainerRelativeShape())
//				   
//			} compactTrailing: {
//				Text(timerInterval: context.state.timerRange, countsDown: true)
//					.monospacedDigit()
//					.foregroundColor(Color("LightIndigo"))
//					.frame(width: 40)
//			} minimal: {
//				Image("IslandCompactIcon")
//					.padding(4)
//					.background(.indigo.gradient, in: ContainerRelativeShape())
//			}
//			.contentMargins(.trailing, 32, for: .expanded)
//			.contentMargins([.leading, .top, .bottom], 6, for: .compactLeading)
//			.contentMargins(.all, 6, for: .minimal)
//			.widgetURL(URL(string: "foodtruck://order/\(context.attributes.nodeNum)"))
//		}
//	}
//}
//
//struct LiveActivityView: View {
//	@Environment(\.colorScheme) private var colorScheme
//	@Environment(\.isLuminanceReduced) var isLuminanceReduced
//	
//	var orderNumber: String
//	var timerRange: ClosedRange<Date>
//	
//	var body: some View {
//		HStack {
//			Image("IslandExpandedIcon")
//				.clipShape(ContainerRelativeShape())
//				.opacity(isLuminanceReduced ? 0.5 : 1.0)
//			OrderInfoView(orderNumber: orderNumber)
//			Spacer()
//			OrderTimerView(timerRange: timerRange)
//		}
//		.tint(.primary)
//		.padding([.leading, .top, .bottom])
//		.padding(.trailing, 32)
//		.activityBackgroundTint(colorScheme == .light ? Color("LiveActivityBackground") : Color("AccentColorDimmed"))
//		.activitySystemActionForegroundColor(.primary)
//	}
//}
//
//struct ExpandedLeadingView: View {
//	var body: some View {
//		Image("IslandExpandedIcon")
//			.clipShape(ContainerRelativeShape())
//	}
//}
//
//struct OrderInfoView: View {
//	@Environment(\.isLuminanceReduced) var isLuminanceReduced
//	
//	var orderNumber: String
//	
//	var body: some View {
//		VStack(alignment: .leading, spacing: 0) {
//			Text("Order \(orderNumber)")
//				.font(.title3)
//				.fontWeight(.semibold)
//				.foregroundStyle(.tint)
//			
//			Text("6 donuts")
//				.font(.subheadline)
//				.fontWeight(.medium)
//				.foregroundStyle(.secondary)
//				.opacity(isLuminanceReduced ? 0.5 : 1.0)
//		}
//	}
//}
//
//struct OrderTimerView: View {
//	@Environment(\.isLuminanceReduced) var isLuminanceReduced
//	
//	var timerRange: ClosedRange<Date>
//	
//	var body: some View {
//		VStack(alignment: .trailing) {
//			Text(timerInterval: timerRange, countsDown: true)
//				.monospacedDigit()
//				.multilineTextAlignment(.trailing)
//				.frame(width: 80)
//				.font(.title3)
//				.fontWeight(.semibold)
//				.foregroundStyle(.tint)
//			Text("Remaining")
//				.font(.subheadline)
//				.fontWeight(.medium)
//				.foregroundStyle(.secondary)
//				.opacity(isLuminanceReduced ? 0.5 : 1.0)
//		}
//	}
//}
//
//struct ExpandedTrailingView: View {
//	var orderNumber: String
//	var timerInterval: ClosedRange<Date>
//	
//	var body: some View {
//		HStack(alignment: .lastTextBaseline) {
//			OrderInfoView(orderNumber: orderNumber)
//			Spacer()
//			OrderTimerView(timerRange: timerInterval)
//		}
//		.tint(Color("LightIndigo"))
//	}
//}
//struct MeshActivityPreviewProvider: PreviewProvider {
//	static let activityAttributes = MeshActivityAttributes(
//		nodeNum: 666, nodeName: "Garth Hydra", channelUtilization: 45.0, airtime: 10.0, activityName: "activity name"
//	)
//	
//	static let state = MeshActivityAttributes.ContentState(
//		timerRange: Date.now...Date(timeIntervalSinceNow: 30))
//	
//	static var previews: some View {
//		activityAttributes
//			.previewContext(state, viewKind: .dynamicIsland(.compact))
//			.previewDisplayName("Compact")
//		
//		activityAttributes
//			.previewContext(state, viewKind: .dynamicIsland(.expanded))
//			.previewDisplayName("Expanded")
//		
//		activityAttributes
//			.previewContext(state, viewKind: .content)
//			.previewDisplayName("Notification")
//		
//		activityAttributes
//			.previewContext(state, viewKind: .dynamicIsland(.minimal))
//			.previewDisplayName("Minimal")
//	}
//}
