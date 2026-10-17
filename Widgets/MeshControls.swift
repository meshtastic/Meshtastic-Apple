//
//  MeshControls.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//
//  Control Center, Lock Screen and Action button controls (iOS 18). Each one
//  opens the app on a screen through OpenMeshScreenIntent. A control can't
//  reach the radio itself — the Bluetooth connection lives in the app — so
//  these hand off to the app rather than act on their own.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Meshtastic brand green, the tint for the controls' symbols.
private let controlTint = Color(red: 0x67 / 255, green: 0xEA / 255, blue: 0x94 / 255)

@available(iOS 18.0, *)
struct MeshMessagesControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "MeshOpenMessages") {
			ControlWidgetButton(action: OpenMeshScreenIntent(screen: .messages)) {
				Label("Messages", systemImage: "message.fill")
			}
			.tint(controlTint)
		}
		.displayName("Mesh Messages")
		.description("Open your Meshtastic messages.")
	}
}

@available(iOS 18.0, *)
struct MeshConnectControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "MeshOpenConnect") {
			ControlWidgetButton(action: OpenMeshScreenIntent(screen: .connect)) {
				Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
			}
			.tint(controlTint)
		}
		.displayName("Connect Radio")
		.description("Open Meshtastic to connect to your radio.")
	}
}

@available(iOS 18.0, *)
struct MeshMapControl: ControlWidget {
	var body: some ControlWidgetConfiguration {
		StaticControlConfiguration(kind: "MeshOpenMap") {
			ControlWidgetButton(action: OpenMeshScreenIntent(screen: .map)) {
				Label("Node Map", systemImage: "map.fill")
			}
			.tint(controlTint)
		}
		.displayName("Mesh Map")
		.description("Open the Meshtastic node map.")
	}
}
