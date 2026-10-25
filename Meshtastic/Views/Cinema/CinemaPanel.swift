//
//  CinemaPanel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
#if os(visionOS)
import SwiftUI

/// The small panel near the viewer in the cinema: which environment to sit in, locking the
/// window in place as the screen, and Leave.
struct CinemaPanel: View {
	@Binding var environment: CinemaEnvironment
	@Binding var isScreenLocked: Bool
	let onLeave: () -> Void

	var body: some View {
		VStack(spacing: 12) {
			Picker(String(localized: "Environment", comment: "Cinema: picker for the place the big screen is set in"), selection: $environment) {
				ForEach(CinemaEnvironment.allCases) { environment in
					Text(environment.title).tag(environment)
				}
			}
			.pickerStyle(.menu)
			CinemaLockButton(isLocked: $isScreenLocked)
			Button(role: .cancel, action: onLeave) {
				Label(String(localized: "Leave", comment: "Cinema: close the immersive cinema and go back to the app window"), systemImage: "xmark")
			}
		}
		.padding(20)
		.glassBackgroundEffect()
	}
}

/// Locks the app window as the cinema screen, hiding the bar that moves it, or unlocks it.
struct CinemaLockButton: View {
	@Binding var isLocked: Bool

	var body: some View {
		Button {
			isLocked.toggle()
		} label: {
			Label(title, systemImage: isLocked ? "lock.fill" : "lock.open")
		}
		.help(title)
	}

	private var title: String {
		isLocked
			? String(localized: "Unlock Screen", comment: "Cinema: let the app window be moved again")
			: String(localized: "Lock Screen", comment: "Cinema: hide the app window's bar, once it has been pushed back where the viewer wants it")
	}
}
#endif
