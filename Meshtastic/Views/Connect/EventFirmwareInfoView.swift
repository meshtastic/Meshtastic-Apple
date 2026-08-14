//
//  EventFirmwareInfoView.swift
//  Meshtastic
//

import Foundation
import SwiftUI

struct EventFirmwareInfoView: View {

	let edition: FirmwareEditions
	let info: EventFirmwareEntity
	let deviceFirmwareVersion: String?
	/// Invoked from the post-event section's update button (the sheet's presenter routes
	/// to the firmware-update flow). Optional so preview/simple presentations stay valid.
	var onUpdateFirmware: (() -> Void)?

	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.dismiss) private var dismiss
	@AppStorage("useEventTheme") private var useEventTheme: Bool = true

	private var accent: Color { info.accentColorValue ?? .accentColor }
	private var displayName: String { info.displayName ?? edition.name }
	private var highlight: Color {
		info.accessibleTintHex(for: colorScheme)
			.flatMap { EventFirmwareEntity.color(fromHex: $0) }
			?? .secondary
	}
	private var headerForeground: Color {
		EventFirmwareEntity.prefersDarkForeground(forHex: info.accentColor) == true ? .black : .white
	}
	private func headingFont(_ size: CGFloat, _ style: Font.TextStyle) -> Font {
		guard useEventTheme else { return .system(style) }
		return EventFirmwareFontResolver.font(
			family: info.themeFontHeading,
			size: size,
			relativeTo: style
		)
	}

	private func bodyFont(_ size: CGFloat, _ style: Font.TextStyle) -> Font {
		guard useEventTheme else { return .system(style) }
		return EventFirmwareFontResolver.font(
			family: info.themeFontBody,
			size: size,
			relativeTo: style
		)
	}

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				header
				if useEventTheme {
					EventFirmwarePaletteRule(colors: info.paletteColors, height: 6)
				}
				List {
					eventEndedSection
					if let welcome = info.welcomeMessage, !welcome.isEmpty {
						Section {
							Text(welcome)
								.font(bodyFont(17, .body))
						}
					}
					if let tagline = info.themeTagline, !tagline.isEmpty {
						Section {
							Text(tagline)
								.font(bodyFont(16, .callout).italic())
						}
					}
					detailsSection
					linksSection
					themeToggleSection
					firmwareSection
				}
				.scrollContentBackground(.hidden)
				.background(Color(.systemGroupedBackground))
			}
			.tint(useEventTheme ? highlight : .accentColor)
			.navigationTitle(Text("Event"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(
						String(localized: "Done", comment: "VoiceOver: dismiss the event info sheet")
					)
				}
			}
		}
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 14) {
				EventFirmwareIcon(
					edition: edition,
					iconURL: info.iconURL,
					size: 48
				)
				VStack(alignment: .leading, spacing: 3) {
					Text(displayName)
						.font(headingFont(22, .title2).weight(.bold))
					if let themeName = info.themeName, !themeName.isEmpty {
						Text(themeName)
							.font(bodyFont(13, .subheadline))
							.opacity(0.88)
					}
				}
				Spacer(minLength: 0)
			}
		}
		.foregroundStyle(headerForeground)
		.padding(.horizontal, 20)
		.padding(.vertical, 18)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(accent)
	}

	/// Post-event call to action, first in the list. `hasEnded()` mirrors Android's
	/// day-granular check (an edition without a valid end date never counts as ended).
	@ViewBuilder
	private var eventEndedSection: some View {
		if info.hasEnded() {
			Section {
				Label {
					Text("\(displayName) has ended. Update your node to the latest stable firmware.")
						.font(bodyFont(16, .callout))
				} icon: {
					Image(systemName: "flag.checkered")
						.foregroundColor(highlight)
				}
				if onUpdateFirmware != nil {
					Button {
						dismiss()
						onUpdateFirmware?()
					} label: {
						Label("Update Firmware", systemImage: "arrow.up.circle.fill")
							.font(bodyFont(17, .body).weight(.semibold))
					}
				}
			} footer: {
				Text("Updates use the app's verified firmware workflow.")
			}
		}
	}

	@ViewBuilder
	private var detailsSection: some View {
		Section {
			if let location = info.location, !location.isEmpty {
				detailRow(icon: "mappin.and.ellipse", text: location)
			}
			if let dates = info.formattedDateRange {
				detailRow(icon: "calendar", text: dates)
			}
			if let domain = info.domain, !domain.isEmpty {
				detailRow(icon: "globe", text: domain)
			}
		}
	}

	@ViewBuilder
	private var firmwareSection: some View {
		if info.firmwareVersion != nil || info.firmwareReleaseNotes != nil {
			Section {
				if let version = info.firmwareVersion {
					HStack {
						Label("Version", systemImage: "cpu")
							.font(.callout)
						Spacer()
						Text(version)
							.font(.callout.monospaced())
							.foregroundColor(.secondary)
					}
				}
				firmwareComparisonRow
				if let notes = info.firmwareReleaseNotes, !notes.isEmpty {
					DisclosureGroup("Release Notes") {
						Text(notes)
							.font(.footnote)
							.foregroundColor(.secondary)
							.padding(.vertical, 2)
					}
				}
			} header: {
				Text("Event Firmware")
			} footer: {
				Text("Firmware packages are not installed from the event metadata feed. Updates use the app's verified firmware workflow.")
			}
		}
	}

	@ViewBuilder
	private var firmwareComparisonRow: some View {
		switch info.firmwareComparison(againstDeviceVersion: deviceFirmwareVersion) {
		case .matches:
			Label("Device is on the event build", systemImage: "checkmark.seal.fill")
				.font(.callout)
				.foregroundColor(.green)
		case .updateAvailable:
			Label("Event metadata lists a different build", systemImage: "info.circle")
				.font(.callout)
				.foregroundColor(.secondary)
		case .unknown:
			EmptyView()
		}
	}

	@ViewBuilder
	private var linksSection: some View {
		if !info.links.isEmpty {
			Section("Links") {
				ForEach(info.links) { link in
					if let url = EventFirmwareURLPolicy.httpsURL(from: link.url) {
						Link(destination: url) {
							HStack {
								Label(link.label, systemImage: "link")
									.font(.callout)
								Spacer()
								Image(systemName: "arrow.up.right")
									.font(.caption)
									.foregroundColor(.secondary)
							}
						}
					}
				}
			}
		}
	}

	private var themeToggleSection: some View {
		Section {
			Toggle(isOn: $useEventTheme) {
				Label("Use Event Theme", systemImage: "paintpalette")
			}
			.tint(highlight)
		} footer: {
			Text("Applies event highlight colors across the app and available fonts inside this sheet. Standard navigation backgrounds remain unchanged.")
		}
	}

	private func detailRow(icon: String, text: String) -> some View {
		HStack(spacing: 10) {
			Image(systemName: icon)
				.foregroundColor(highlight)
				.frame(width: 22)
			Text(text)
				.font(bodyFont(15, .callout))
			Spacer(minLength: 0)
		}
	}
}

struct EventFirmwareIcon: View {
	let edition: FirmwareEditions
	let iconURL: URL?
	var size: CGFloat = 40

	@Environment(\.colorScheme) private var colorScheme
	@State private var hostedImage: UIImage?

	var body: some View {
		Group {
			if let hostedImage {
				Image(uiImage: hostedImage)
					.resizable()
					.scaledToFit()
			} else if let assetName = edition.bundledIconAssetName {
				Image(assetName)
					.resizable()
					.scaledToFit()
			} else {
				Image(colorScheme == .dark ? "logo-white" : "logo-black")
					.resizable()
					.scaledToFit()
					.padding(size * 0.18)
			}
		}
		.frame(width: size, height: size)
		.background(Color(.systemBackground))
		.clipShape(Circle())
		.overlay {
			Circle()
				.strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
		}
		.task(id: iconURL) {
			hostedImage = await EventFirmwareIconLoader.load(iconURL)
		}
	}
}

private enum EventFirmwareIconLoader {
	nonisolated static func load(_ url: URL?) async -> UIImage? {
		guard let url, url.scheme?.lowercased() == "https" else { return nil }
		var request = URLRequest(url: url)
		request.timeoutInterval = 15
		do {
			let (bytes, response) = try await URLSession.shared.bytes(for: request)
			guard let response = response as? HTTPURLResponse,
				  (200..<300).contains(response.statusCode),
				  response.expectedContentLength <= Int64(EventFirmwareImageValidator.maximumEncodedBytes),
				  response.mimeType == "image/png" || response.mimeType == "image/jpeg" else {
				return nil
			}
			var data = Data()
			if response.expectedContentLength > 0 {
				data.reserveCapacity(Int(response.expectedContentLength))
			}
			for try await byte in bytes {
				guard data.count < EventFirmwareImageValidator.maximumEncodedBytes else {
					return nil
				}
				data.append(byte)
			}
			return EventFirmwareImageValidator.image(from: data)
		} catch {
			return nil
		}
	}
}
