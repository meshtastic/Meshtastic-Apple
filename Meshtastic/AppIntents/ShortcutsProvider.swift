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
		// Feature 021 (W-11): the radio a command uses when it doesn't name one.
		AppShortcut(intent: SetMeshtasticRadioIntent(),
					phrases: ["Set my \(.applicationName) radio",
							  "Change my \(.applicationName) radio",
							  "Make \(\.$radio) my \(.applicationName) radio",
							  "Use \(\.$radio) for \(.applicationName)"],
					shortTitle: "Set Radio",
					systemImageName: "antenna.radiowaves.left.and.right")
		AppShortcut(intent: DisconnectNodeIntent(),
					phrases: ["Disconnect \(.applicationName) node",
							  "Disconnect my \(.applicationName) node",
							   "Disconnect from \(.applicationName)",
							   "Disconnect \(.applicationName)"],
					shortTitle: "Disconnect",
					systemImageName: "antenna.radiowaves.left.and.right.slash")
	}
}
