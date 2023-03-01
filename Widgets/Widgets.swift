//
//  WidgetsBundle.swift
//  Widgets
//
//  Created by Garth Vander Houwen on 2/28/23.
//

import WidgetKit
import SwiftUI

@main
struct Widgets: WidgetBundle {
    var body: some Widget {
		
		// MARK: - Live Activity Widgets
		#if canImport(ActivityKit)
		MeshActivityWidget()
		#endif
    }
}
