import SwiftUI
import UIKit

extension PersistenceBootstrap.State {
	var accessibilityAnnouncement: String? {
		switch self {
		case .migrating:
			"Updating local data. This may take a minute. Keep Meshtastic open."
		case .failed:
			"Local data update failed. Retry is available."
		case .waiting, .waitingForProtectedData, .preparing, .ready:
			nil
		}
	}
}

struct MigrationBootstrapView: View {
	let state: PersistenceBootstrap.State
	let retry: () -> Void

	@Environment(\.colorScheme) private var colorScheme

	private var appIconImage: UIImage? {
		Self.appIconImage(
			iconName: UIApplication.shared.alternateIconName,
			colorScheme: colorScheme
		)
	}

	static func appIconImage(iconName: String?, colorScheme: ColorScheme) -> UIImage? {
		let resolvedIconName = iconName ?? "AppIcon"
		let thumbnailName = colorScheme == .dark
			? "\(resolvedIconName)_Dark_Thumb"
			: "\(resolvedIconName)_Thumb"
		let defaultThumbnailName = colorScheme == .dark ? "AppIcon_Dark_Thumb" : "AppIcon_Thumb"
		return UIImage(named: thumbnailName)
			?? UIImage(named: defaultThumbnailName)
	}

	var body: some View {
		ZStack {
			Color(.systemBackground)
				.ignoresSafeArea()
			VStack(spacing: 16) {
				if let appIconImage {
					Image(uiImage: appIconImage)
						.resizable()
						.scaledToFit()
						.frame(width: 88, height: 88)
						.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
						.accessibilityHidden(true)
				}

				switch state {
				case .failed(let message):
					Image(systemName: "exclamationmark.triangle.fill")
						.foregroundStyle(.orange)
						.accessibilityHidden(true)
					Text("Local data update failed")
						.font(.headline)
						.accessibilityAddTraits(.isHeader)
						.accessibilityIdentifier("migration-bootstrap-title")
					Text(message)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
					Button("Retry", action: retry)
						.buttonStyle(.borderedProminent)
						.accessibilityIdentifier("migration-bootstrap-retry")
				case .migrating:
					ProgressView()
						.accessibilityHidden(true)
					Text("Updating local data…")
						.font(.headline)
						.accessibilityAddTraits(.isHeader)
						.accessibilityIdentifier("migration-bootstrap-title")
					Text("This may take a minute. Keep Meshtastic open.")
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.accessibilityLabel("This may take a minute. Keep Meshtastic open while local data is updated")
						.accessibilityIdentifier("migration-bootstrap-instruction")
				case .waiting, .waitingForProtectedData, .preparing, .ready:
					ProgressView()
						.accessibilityHidden(true)
					Text("Opening Meshtastic…")
						.font(.headline)
						.accessibilityAddTraits(.isHeader)
						.accessibilityIdentifier("migration-bootstrap-title")
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
