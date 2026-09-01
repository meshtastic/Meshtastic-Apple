import SwiftUI
import UIKit

extension PersistenceController.State {
	var accessibilityAnnouncement: String? {
		switch self {
		case .migrating:
			"Updating local data. This may take a minute. Keep Meshtastic open."
		case .failed:
			"Local data update failed. Retry is available."
		case .idle, .waitingForProtectedData, .preparing, .ready:
			nil
		}
	}
}

struct MigrationBootstrapView: View {
	let state: PersistenceController.State
	let retry: () -> Void

	var body: some View {
		ZStack {
			Color(.systemBackground)
				.ignoresSafeArea()
			VStack(spacing: 16) {
				switch state {
				case .failed(let message):
					Image(systemName: "exclamationmark.triangle.fill")
						.foregroundStyle(.orange)
						.accessibilityHidden(true)
					Text("Local data update failed")
						.font(.headline)
						.accessibilityAddTraits(.isHeader)
					Text(message)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
					Button("Retry", action: retry)
						.buttonStyle(.borderedProminent)
				case .migrating:
					ProgressView()
						.accessibilityHidden(true)
					Text("Updating local data…")
						.font(.headline)
						.accessibilityAddTraits(.isHeader)
					Text("This may take a minute. Keep Meshtastic open.")
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				case .waitingForProtectedData:
					ProgressView()
						.accessibilityHidden(true)
					Text("Unlock this device to continue")
						.font(.headline)
						.accessibilityAddTraits(.isHeader)
				case .idle, .preparing, .ready:
					ProgressView()
						.accessibilityHidden(true)
					Text("Opening Meshtastic…")
						.font(.headline)
						.accessibilityAddTraits(.isHeader)
				}
			}
			.padding(32)
		}
		.onChange(of: state) { _, newState in
			guard UIAccessibility.isVoiceOverRunning,
				  let announcement = newState.accessibilityAnnouncement else { return }
			UIAccessibility.post(notification: .announcement, argument: announcement)
		}
	}
}
