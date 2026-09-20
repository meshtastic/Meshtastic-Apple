//
//  LockdownSection.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import SwiftUI

/// Settings section surfacing lockdown session status, Lock Now, and Forget
/// Stored Passphrase. Hidden when the connected device does not report any
/// lockdown state (i.e. non-hardened firmware that never sends LockdownStatus).
struct LockdownSection: View {
	@ObservedObject var lockdown: LockdownCoordinator
	@Binding var showLockNowAlert: Bool

	var body: some View {
		switch lockdown.state {
		case .unlocked(let bootsRemaining, let validUntilEpoch):
			Section(header: Text("Lockdown")) {
				Label {
					VStack(alignment: .leading) {
						Text("Session status")
						Text("Unlocked")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				} icon: {
					Image(systemName: "lock.open.fill")
						.foregroundStyle(.green)
				}

				if bootsRemaining > 0 {
					Label("Boots remaining: \(bootsRemaining)", systemImage: "powerplug")
				}

				if validUntilEpoch == 0 {
					Label("No time limit", systemImage: "infinity")
				} else {
					Label {
						Text("Expires \(Date(timeIntervalSince1970: TimeInterval(validUntilEpoch)).formatted(date: .abbreviated, time: .shortened))")
					} icon: {
						Image(systemName: "clock")
					}
				}

				Button(role: .destructive) {
					showLockNowAlert = true
				} label: {
					Label("Lock Now", systemImage: "lock.fill")
				}
				.alert("Lock device now?", isPresented: $showLockNowAlert) {
					Button("Cancel", role: .cancel) {}
					Button("Lock", role: .destructive) {
						lockdown.lockNow()
					}
				} message: {
					Text("This revokes the current session and reboots the device locked. You will need the passphrase to reconnect.")
				}

				Button {
					lockdown.forgetCachedPassphrase()
				} label: {
					Label("Forget Stored Passphrase", systemImage: "key.slash")
				}
			}
		case .none:
			// Non-lockdown firmware or pre-handshake. Hide the section entirely.
			EmptyView()
		default:
			// .needsProvision / .locked / .unlockFailed / .unlockBackoff are
			// surfaced via the full-screen sheet in ContentView; do not
			// duplicate them in Settings.
			EmptyView()
		}
	}
}
