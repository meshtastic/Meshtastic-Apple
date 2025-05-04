//
//  OSLogEntryLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/28/24.
//

import OSLog
import SwiftUI

/// Extensions to allow rendering of the emoji string and log leve coloring in the grid of OSLogEntryLog items
extension OSLogEntryLog.Level {
	var description: String {
		switch self {
		case .undefined: "undefined"
		case .debug: "🪲 Debug"
		case .info: "ℹ️ Info"
		case .notice: "⚠️ Notice"
		case .error: "🚨 Error"
		case .fault: "💥 Fault"
		@unknown default: "Default".localized
		}
	}
	var color: Color {
		switch self {
		case .undefined: .green
		case .debug: .indigo
		case .info: .green
		case .notice: .orange
		case .error: .red
		case .fault: .red
		@unknown default: .green
		}
	}
}
