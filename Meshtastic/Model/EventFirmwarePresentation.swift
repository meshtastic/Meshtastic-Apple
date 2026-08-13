//
//  EventFirmwarePresentation.swift
//  Meshtastic
//

import SwiftData
import SwiftUI

// MARK: - Presentation

/// The event identity currently allowed to affect app presentation.
///
/// Keeping this context in one environment value makes the trust boundary explicit: views only
/// receive event branding when a connected non-vanilla edition has a matching cached manifest row.
struct EventFirmwarePresentation {
	let edition: FirmwareEditions
	let info: EventFirmwareEntity
	let deviceFirmwareVersion: String?

	static func resolve(
		isConnected: Bool,
		edition: FirmwareEditions,
		metadata: [EventFirmwareEntity],
		deviceFirmwareVersion: String?
	) -> EventFirmwarePresentation? {
		guard isConnected,
			  edition.isEvent,
			  let info = metadata.first(where: { $0.edition == edition.editionKey }) else {
			return nil
		}
		return EventFirmwarePresentation(
			edition: edition,
			info: info,
			deviceFirmwareVersion: deviceFirmwareVersion
		)
	}
}

// MARK: - Environment

private struct EventFirmwarePresentationKey: EnvironmentKey {
	static let defaultValue: EventFirmwarePresentation? = nil
}

private struct OpenEventFirmwareInfoKey: EnvironmentKey {
	static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
	var eventFirmwarePresentation: EventFirmwarePresentation? {
		get { self[EventFirmwarePresentationKey.self] }
		set { self[EventFirmwarePresentationKey.self] = newValue }
	}

	var openEventFirmwareInfo: () -> Void {
		get { self[OpenEventFirmwareInfoKey.self] }
		set { self[OpenEventFirmwareInfoKey.self] = newValue }
	}
}

// MARK: - Tint

/// Applies the event's contrast-safe tint above the root presentation modifiers so tabs,
/// navigation actions, and app-level sheets all inherit the same highlight color.
struct EventFirmwareTintScope<Content: View>: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.colorScheme) private var colorScheme
	@AppStorage("useEventTheme") private var useEventTheme: Bool = true
	@Query private var eventFirmwareEditions: [EventFirmwareEntity]
	@State private var cachedTint: Color = .accentColor

	private let content: Content

	init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	private struct TintInputs: Equatable {
		let isConnected: Bool
		let editionRawValue: Int
		let connectedVersion: String?
		let usesDarkAppearance: Bool
		let useEventTheme: Bool
		let themeAccentColor: String?
		let themeSecondaryColor: String?
		let palette: [String]
	}

	private var matchingInfo: EventFirmwareEntity? {
		eventFirmwareEditions.first {
			$0.edition == accessoryManager.firmwareEdition.editionKey
		}
	}

	private var tintInputs: TintInputs {
		TintInputs(
			isConnected: accessoryManager.isConnected,
			editionRawValue: accessoryManager.firmwareEdition.rawValue,
			connectedVersion: accessoryManager.connectedVersion,
			usesDarkAppearance: colorScheme == .dark,
			useEventTheme: useEventTheme,
			themeAccentColor: matchingInfo?.themeAccentColor,
			themeSecondaryColor: matchingInfo?.themeSecondaryColor,
			palette: matchingInfo?.brandPaletteHexes ?? []
		)
	}

	private func resolvedTint() -> Color {
		guard useEventTheme,
			  let presentation = EventFirmwarePresentation.resolve(
				isConnected: accessoryManager.isConnected,
				edition: accessoryManager.firmwareEdition,
				metadata: eventFirmwareEditions,
				deviceFirmwareVersion: accessoryManager.connectedVersion
			  ),
			  let tintHex = presentation.info.accessibleTintHex(for: colorScheme),
			  let tint = EventFirmwareEntity.color(fromHex: tintHex) else {
			return .accentColor
		}
		return tint
	}

	private func updateTint() {
		cachedTint = resolvedTint()
	}

	var body: some View {
		content
			.tint(cachedTint)
			.onAppear(perform: updateTint)
			.onChange(of: tintInputs) {
				updateTint()
			}
	}
}

// MARK: - Palette

struct EventFirmwarePaletteRule: View {
	let colors: [Color]
	var height: CGFloat = 3

	@ViewBuilder
	var body: some View {
		if colors.count == 1, let color = colors.first {
			Rectangle()
				.fill(color)
				.frame(height: height)
				.accessibilityHidden(true)
		} else if colors.count > 1 {
			LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
				.frame(height: height)
				.accessibilityHidden(true)
		}
	}
}
