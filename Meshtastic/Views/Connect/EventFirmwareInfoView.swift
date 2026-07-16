//
//  EventFirmwareInfoView.swift
//  Meshtastic
//
//  The tappable event info surface (design#120, gap #3): welcome message, location,
//  dates, palette, links, and the event's firmware build — plus the "Use event theme"
//  opt-out toggle. Presented from the event branding badge on the Connect screen.
//

import SwiftUI
import SwiftData

struct EventFirmwareInfoView: View {

	let edition: FirmwareEditions
	let info: EventFirmwareEntity
	/// The connected node, used by the firmware-update flow reached from this sheet.
	let node: NodeInfoEntity?
	/// The connected device's reported firmware version, for the build comparison.
	let deviceFirmwareVersion: String?

	@Environment(\.dismiss) private var dismiss
	/// Shared with the Connect screen's ambient wash — toggling here updates both.
	@AppStorage("useEventTheme") private var useEventTheme: Bool = true

	private var accent: Color { info.accentColorValue ?? .accentColor }
	private var displayName: String { info.displayName ?? edition.name }

	/// Heading font from the edition's `theme.fonts` when the family is available and the theme
	/// is enabled; otherwise the system font. (Google font families aren't bundled today, so
	/// this resolves to system until a font provider ships — the resolver is future-proof.)
	private func headingFont(_ size: CGFloat, _ style: Font.TextStyle) -> Font {
		guard useEventTheme else { return .system(style) }
		return EventFirmwareFontResolver.font(family: info.themeFontHeading, size: size, relativeTo: style)
	}

	private func bodyFont(_ size: CGFloat, _ style: Font.TextStyle) -> Font {
		guard useEventTheme else { return .system(style) }
		return EventFirmwareFontResolver.font(family: info.themeFontBody, size: size, relativeTo: style)
	}

	var body: some View {
		NavigationStack {
			List {
				header
				if let welcome = info.welcomeMessage, !welcome.isEmpty {
					Section {
						Text(welcome)
							.font(bodyFont(17, .body))
					}
				}
				detailsSection
				if info.paletteColors.count > 1 {
					paletteSection
				}
				firmwareSection
				linksSection
				themeToggleSection
			}
			.scrollContentBackground(.hidden)
			.background {
				ZStack {
					Color(.systemGroupedBackground)
					if useEventTheme {
						LinearGradient(
							colors: [accent.opacity(0.20), .clear],
							startPoint: .top,
							endPoint: .center
						)
						.ignoresSafeArea()
					}
				}
			}
			.navigationTitle(Text("Event"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
	}

	// MARK: - Sections

	@ViewBuilder
	private var header: some View {
		Section {
			HStack(spacing: 14) {
				EventFirmwareIcon(iconUrl: info.iconUrl, accent: accent, size: 56)
				VStack(alignment: .leading, spacing: 3) {
					Text(displayName)
						.font(headingFont(22, .title2).weight(.bold))
						.foregroundColor(accent)
					if let themeName = info.themeName, !themeName.isEmpty {
						Text(themeName)
							.font(bodyFont(13, .subheadline))
							.foregroundColor(.secondary)
					}
				}
			}
			.padding(.vertical, 4)
			if let tagline = info.themeTagline, !tagline.isEmpty {
				Text(tagline)
					.font(bodyFont(14, .callout).italic())
					.foregroundColor(.secondary)
			}
		}
		.listRowBackground(Color.clear)
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
	private var paletteSection: some View {
		Section("Theme") {
			HStack(spacing: 8) {
				ForEach(Array(info.paletteColors.enumerated()), id: \.offset) { _, color in
					RoundedRectangle(cornerRadius: 6, style: .continuous)
						.fill(color)
						.frame(height: 28)
						.overlay(
							RoundedRectangle(cornerRadius: 6, style: .continuous)
								.strokeBorder(Color.primary.opacity(0.1))
						)
				}
			}
			.padding(.vertical, 2)
		}
	}

	@ViewBuilder
	private var firmwareSection: some View {
		if info.firmwareVersion != nil || info.firmwareZipUrl != nil {
			Section("Event Firmware") {
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
				NavigationLink {
					Firmware(node: node)
				} label: {
					Label("Firmware Update", systemImage: "arrow.down.circle")
				}
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
			Label("A different build is available", systemImage: "arrow.up.circle")
				.font(.callout)
				.foregroundColor(accent)
		case .unknown:
			EmptyView()
		}
	}

	@ViewBuilder
	private var linksSection: some View {
		if !info.links.isEmpty {
			Section("Links") {
				ForEach(info.links) { link in
					if let url = URL(string: link.url) {
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

	@ViewBuilder
	private var themeToggleSection: some View {
		Section {
			Toggle(isOn: $useEventTheme) {
				Label("Use Event Theme", systemImage: "paintpalette")
			}
			.tint(accent)
		} footer: {
			Text("Applies a subtle accent wash and the event's fonts across the app. The event branding stays visible either way.")
		}
	}

	// MARK: - Helpers

	private func detailRow(icon: String, text: String) -> some View {
		HStack(spacing: 10) {
			Image(systemName: icon)
				.foregroundColor(accent)
				.frame(width: 22)
			Text(text)
				.font(bodyFont(15, .callout))
			Spacer(minLength: 0)
		}
	}
}

/// The hosted event icon (`iconUrl`), or an accent-tinted sparkles placeholder while loading /
/// when no icon is published for the edition.
struct EventFirmwareIcon: View {
	let iconUrl: String?
	let accent: Color
	var size: CGFloat = 40

	var body: some View {
		Group {
			if let iconUrl, let url = URL(string: iconUrl) {
				AsyncImage(url: url) { phase in
					switch phase {
					case .success(let image):
						image.resizable().scaledToFit()
					default:
						placeholder
					}
				}
			} else {
				placeholder
			}
		}
		.frame(width: size, height: size)
		.background(accent.opacity(0.12))
		.clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
	}

	private var placeholder: some View {
		Image(systemName: "sparkles")
			.font(.system(size: size * 0.5))
			.foregroundColor(accent)
	}
}
