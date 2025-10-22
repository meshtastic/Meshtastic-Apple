//
//  ShortcutsProvider.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/24/24.
//

#if canImport(AppIntents)
import Foundation
import AppIntents

@available(iOS 16.0, *)
struct ShortcutsProvider: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(intent: ShutDownNodeIntent(),
					phrases: ["Shut down \(.applicationName) node",
							  "Shut down my \(.applicationName) node",
							  "Turn off \(.applicationName) node",
							  "Power down \(.applicationName) node",
							  "Deactivate \(.applicationName) node"],
					shortTitle: "Shut Down",
					systemImageName: "power")

		AppShortcut(intent: RestartNodeIntent(),
					phrases: ["Restart \(.applicationName) node",
							  "Restart my \(.applicationName) node",
							  "Reboot \(.applicationName) node",
							  "Reboot my \(.applicationName) node"],
					shortTitle: "Restart",
					systemImageName: "arrow.circlepath")

		AppShortcut(intent: MessageChannelIntent(),
					phrases: ["Message a \(.applicationName) channel",
							  "Send a \(.applicationName) group message"],
					shortTitle: "Group Message",
					systemImageName: "message")
		AppShortcut(intent: DisconnectNodeIntent(),
					phrases: ["Disconnect \(.applicationName) node",
							  "Disconnect my \(.applicationName) node",
							   "Disconnect from \(.applicationName)",
							   "Disconnect \(.applicationName)"],
					shortTitle: "Disconnect",
					systemImageName: "antenna.radiowaves.left.and.right.slash")
	}
}

#endif