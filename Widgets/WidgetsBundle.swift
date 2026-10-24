//
//  WidgetsBundle.swift
//  Widgets
//
//  Created by Garth Vander Houwen on 2/28/23.
//

import WidgetKit
import SwiftUI

@main
struct WidgetsBundle: WidgetBundle {
	var body: some Widget {
		MeshLocalStatsWidget()
		MeshNodeTrackerWidget()
		MeshMessagesWidget()
		MeshNodeMapWidget()
		MeshTraceRouteWidget()
		#if !targetEnvironment(macCatalyst)
		#if canImport(ActivityKit)
		MeshLiveActivity()
		#endif
		if #available(iOS 18.0, *) {
			MeshMessagesControl()
			MeshConnectControl()
			MeshMapControl()
		}
		#endif
	}
}
