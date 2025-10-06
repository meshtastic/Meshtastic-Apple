//
//  TileHeightKeys.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/21/25.
//

import SwiftUI

struct WeatherKitTilesHeightKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		// This method combines values from multiple child views if needed
		value = max(value, nextValue())
	}
}

struct EnvironmentMetricsTilesHeightKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		// This method combines values from multiple child views if needed
		value = max(value, nextValue())
	}
}
