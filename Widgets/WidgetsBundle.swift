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
        // Widgets()
		#if canImport(ActivityKit)
		WidgetsLiveActivity()
		#endif

    }
}
