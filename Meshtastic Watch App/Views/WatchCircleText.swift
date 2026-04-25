//
//  WatchCircleText.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI

/// A small circle showing the node's short name, colored by node number.
/// Watch-only equivalent of the iOS `CircleText` view.
struct WatchCircleText: View {
	var text: String
	var color: Color
	var circleSize: CGFloat = 28

	var body: some View {
		ZStack {
			Circle()
				.fill(color)
				.frame(width: circleSize, height: circleSize)
			Text(text)
				.frame(width: circleSize * 0.9, height: circleSize * 0.9, alignment: .center)
				.foregroundColor(color.isWatchLight ? .black : .white)
				.minimumScaleFactor(0.001)
				.font(.system(size: 1300))
		}
	}

	/// Derives a `Color` from a Meshtastic node number, matching the iOS
	/// `UIColor(hex:)` algorithm so circles look the same on both platforms.
	static func color(for nodeNum: UInt32) -> Color {
		let red = Double((nodeNum & 0xFF0000) >> 16) / 255.0
		let green = Double((nodeNum & 0x00FF00) >> 8) / 255.0
		let blue = Double(nodeNum & 0x0000FF) / 255.0
		return Color(red: red, green: green, blue: blue)
	}
}
