//
//  ShortcutsProvider.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/24/24.
//

import Foundation
import AppIntents

struct ShortcutsProvider: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(intent: ShutDownNodeIntent(),
					phrases: ["Shut down node in \(.applicationName)",
							  "Turn off node in \(.applicationName)",
							  "Power down node in \(.applicationName)",
							  "Deactivate node in \(.applicationName)"],
					shortTitle: "Shut Down Node",
					systemImageName: "power")

		AppShortcut(intent: RestartNodeIntent(),
					phrases: ["Restart node in \(.applicationName)",
							  "Reboot node in \(.applicationName)",
							  "Reset node in \(.applicationName)",
							  "Start node again in \(.applicationName)"],
					shortTitle: "Restart Node",
					systemImageName: "arrow.circlepath")

		AppShortcut(intent: MessageChannelIntent(),
					phrases: ["Message channel in \(.applicationName)"],
					shortTitle: "Message Channel",
					systemImageName: "message")
	}
}
