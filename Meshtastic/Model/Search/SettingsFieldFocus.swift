//
//  SettingsFieldFocus.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import SwiftUI

/// The control a search result asked for, handed to whichever screen owns it.
///
/// A result names one control, not just a screen, so the screen it opens scrolls to that
/// control and marks it. This rides in the environment rather than the navigation path:
/// the path is a plain enum that also encodes deep links and restored state, and a screen
/// reached any other way has no control to single out.
struct SettingsFieldFocus {
	/// The field to scroll to, or nil when the screen was opened some other way.
	var target: FieldIdentity?
	/// Called once a screen has taken it, so leaving and coming back does not scroll again.
	var clear: () -> Void = {}
}

private struct SettingsFieldFocusKey: EnvironmentKey {
	static let defaultValue = SettingsFieldFocus()
}

extension EnvironmentValues {
	var settingsFieldFocus: SettingsFieldFocus {
		get { self[SettingsFieldFocusKey.self] }
		set { self[SettingsFieldFocusKey.self] = newValue }
	}
}
