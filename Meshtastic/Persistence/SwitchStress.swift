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

	private static var requestedCycles: Int {
		guard let idx = CommandLine.arguments.firstIndex(of: "-switch-stress"),
			  idx + 1 < CommandLine.arguments.count,
			  let n = Int(CommandLine.arguments[idx + 1]) else { return 6 }
		return n
	}

	/// Waits for discovery to surface at least two TCP devices, then alternates full
	/// switch cycles between them, logging a machine-greppable verdict per cycle.
	static func runIfNeeded(accessoryManager: AccessoryManager, appState: AppState) async {
		guard isActive else { return }
		let cycles = requestedCycles
		Logger.services.warning("🧪 [SwitchStress] armed: \(cycles, privacy: .public) cycles")

		// Let launch settle, then wait (up to 30s) for two distinct TCP devices.
		try? await Task.sleep(for: .seconds(5))
		var targets: [Device] = []
		for _ in 0..<60 {
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
		for cycle in 1...cycles {
			// Always switch to the device we are NOT currently connected to.
			let currentNum = accessoryManager.activeDeviceNum
			let candidates = accessoryManager.devices.filter { $0.transportType == .tcp }
			guard let target = candidates.first(where: { $0.num != currentNum }) ?? candidates.first else {
				Logger.services.error("🧪 [SwitchStress] cycle \(cycle, privacy: .public): no target visible, waiting")
				try? await Task.sleep(for: .seconds(3))
				continue
			}
			Logger.services.warning("🧪 [SwitchStress] cycle \(cycle, privacy: .public)/\(cycles, privacy: .public): switching to \(target.name, privacy: .public) (num \(target.num.map(String.init) ?? "?", privacy: .public))")

			await switchToDevice(target, accessoryManager: accessoryManager, appState: appState)

			// Give the connect + node dump a window, then judge.
			var landed = false
			for _ in 0..<40 {
				try? await Task.sleep(for: .milliseconds(500))
				if accessoryManager.isConnected,
				   let now = accessoryManager.activeDeviceNum,
				   target.num == nil || now == target.num {
					landed = true
					break
				}
			}
			if landed {
				passes += 1
				Logger.services.warning("🧪 [SwitchStress] cycle \(cycle, privacy: .public): PASS (connected to \(accessoryManager.activeDeviceNum.map(String.init) ?? "?", privacy: .public))")
			} else {
				failures += 1
				Logger.services.error("🧪 [SwitchStress] cycle \(cycle, privacy: .public): FAIL (isConnected=\(accessoryManager.isConnected, privacy: .public) active=\(accessoryManager.activeDeviceNum.map(String.init) ?? "nil", privacy: .public) wanted=\(target.num.map(String.init) ?? "?", privacy: .public))")
			}
			// Brief inter-cycle settle so the verdict isn't tangled with the next teardown.
			try? await Task.sleep(for: .seconds(2))
		}
		Logger.services.warning("🧪 [SwitchStress] DONE: \(passes, privacy: .public) pass / \(failures, privacy: .public) fail of \(cycles, privacy: .public)")
	}
}
#endif
