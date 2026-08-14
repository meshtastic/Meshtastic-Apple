//
//  SwitchStress.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/13/26.
//
//  DEBUG-only node-switch stress harness. Launch with `-switch-stress N` while two or more
//  TCP radios (e.g. meshtastic-mcp replay instances) are discoverable, and it drives the real
//  `switchToDevice` flow back and forth N times — the exact production path behind the
//  "repeatable crash when switching nodes" reports (Datadog 324bff02 + the UICollectionView
//  batch-update SIGABRT). Follows the MarketingCapture in-app-harness pattern: zero effect
//  unless the launch argument is present, compiled out of Release entirely.
//

#if DEBUG
import Foundation
import OSLog
import SwiftUI

@MainActor
enum SwitchStress {
	static var isActive: Bool {
		CommandLine.arguments.contains("-switch-stress")
	}

	/// The switch flow bumps `appState.databaseResetID`, which recreates ContentView and
	/// re-runs its `.task` — without this guard the harness re-arms once per switch and the
	/// superseded (cancelled) instances spin their judge loops to instant FAILs while still
	/// issuing competing `switchToDevice` calls.
	private static var started = false

	private static var requestedCycles: Int {
		guard let idx = CommandLine.arguments.firstIndex(of: "-switch-stress"),
			  idx + 1 < CommandLine.arguments.count,
			  let n = Int(CommandLine.arguments[idx + 1]) else { return 6 }
		return n
	}

	static func runIfNeeded(accessoryManager: AccessoryManager, appState: AppState) async {
		guard isActive, !started else { return }
		started = true
		// Unstructured task: the calling `.task` dies with the old ContentView identity on
		// every databaseResetID bump, and a structured child would be cancelled with it.
		Task {
			await run(accessoryManager: accessoryManager, appState: appState)
		}
	}

	/// Waits for discovery to surface at least two TCP devices, then alternates full
	/// switch cycles between them, logging a machine-greppable verdict per cycle.
	private static func run(accessoryManager: AccessoryManager, appState: AppState) async {
		let cycles = requestedCycles
		Logger.services.warning("🧪 [SwitchStress] armed: \(cycles, privacy: .public) cycles")

		// Let launch settle, then wait (up to 30s) for two distinct TCP devices. Kick
		// discovery every pass (idempotent): an auto-reconnect to the preferred device at
		// launch stops discovery and clears the list before this first scan can run.
		try? await Task.sleep(for: .seconds(5))
		var targets: [Device] = []
		for _ in 0..<60 {
			accessoryManager.startDiscovery()
			targets = accessoryManager.devices.filter { $0.transportType == .tcp }
			if targets.count >= 2 { break }
			try? await Task.sleep(for: .milliseconds(500))
		}
		guard targets.count >= 2 else {
			Logger.services.error("🧪 [SwitchStress] ABORT: found \(targets.count, privacy: .public) TCP devices, need 2")
			return
		}
		Logger.services.warning("🧪 [SwitchStress] targets: \(targets.prefix(2).map(\.name).joined(separator: " ⇄ "), privacy: .public)")

		var passes = 0
		var failures = 0
		// Alternate by transport identifier (IP:port) — stable across discovery refreshes,
		// unlike `num`, which stays nil for discovered-but-never-connected TCP devices.
		var lastIdentifier: String?
		for cycle in 1...cycles {
			// Connecting stops discovery (AccessoryManager+Connect) and clears the device
			// list; the Connect tab normally restarts it on appear. Kick it ourselves and
			// wait for the other radio to reappear instead of burning the cycle.
			accessoryManager.startDiscovery()
			var target: Device?
			for _ in 0..<30 {
				let connectedIdentifier = accessoryManager.activeConnection?.device.identifier
				let candidates = accessoryManager.devices.filter { $0.transportType == .tcp }
				target = candidates.first(where: { $0.identifier != connectedIdentifier && $0.identifier != lastIdentifier })
					?? candidates.first(where: { $0.identifier != connectedIdentifier })
				if target != nil { break }
				try? await Task.sleep(for: .milliseconds(500))
			}
			guard let target else {
				failures += 1
				Logger.services.error("🧪 [SwitchStress] cycle \(cycle, privacy: .public): FAIL (no other TCP device reappeared in 15s)")
				continue
			}
			lastIdentifier = target.identifier
			Logger.services.warning("🧪 [SwitchStress] cycle \(cycle, privacy: .public)/\(cycles, privacy: .public): switching to \(target.name, privacy: .public) @ \(target.identifier, privacy: .public)")

			await switchToDevice(target, accessoryManager: accessoryManager, appState: appState)

			// Give the connect + node dump a window, then judge by connected identifier.
			var landed = false
			for _ in 0..<40 {
				try? await Task.sleep(for: .milliseconds(500))
				if accessoryManager.isConnected,
				   accessoryManager.activeConnection?.device.identifier == target.identifier {
					landed = true
					break
				}
			}
			if landed {
				passes += 1
				Logger.services.warning("🧪 [SwitchStress] cycle \(cycle, privacy: .public): PASS (connected to \(target.identifier, privacy: .public))")
			} else {
				failures += 1
				let current = accessoryManager.activeConnection?.device.identifier ?? "nil"
				Logger.services.error("🧪 [SwitchStress] cycle \(cycle, privacy: .public): FAIL (isConnected=\(accessoryManager.isConnected, privacy: .public) connected=\(current, privacy: .public) wanted=\(target.identifier, privacy: .public))")
			}
			// Brief inter-cycle settle so the verdict isn't tangled with the next teardown.
			try? await Task.sleep(for: .seconds(2))
		}
		Logger.services.warning("🧪 [SwitchStress] DONE: \(passes, privacy: .public) pass / \(failures, privacy: .public) fail of \(cycles, privacy: .public)")
	}
}
#endif
