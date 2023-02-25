//
//  MeshtasticWidgetsBundle.swift
//  MeshtasticWidgets
//
//  Created by Garth Vander Houwen on 2/23/23.
//

import WidgetKit
import SwiftUI

@main
struct MeshtasticWidgetsBundle: WidgetBundle {
    var body: some Widget {
		
		// MARK: - Live Activity Widgets
		#if canImport(ActivityKit)
		//MeshActivityWidget()
		#endif
    }
}
