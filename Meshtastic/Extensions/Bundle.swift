//
//  Bundle.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/25/23.
//

import Foundation

extension Bundle {
	public var appName: String { getInfo("CFBundleName") }
	public var displayName: String { getInfo("CFBundleDisplayName") }
	public var language: String { getInfo("CFBundleDevelopmentRegion") }
	public var identifier: String { getInfo("CFBundleIdentifier") }
	public var copyright: String { getInfo("NSHumanReadableCopyright").replacingOccurrences(of: "\\\\n", with: "\n") }

	public var appBuild: String { getInfo("CFBundleVersion") }
	public var appVersionLong: String { getInfo("CFBundleShortVersionString") }
	// public var appVersionShort: String { getInfo("CFBundleShortVersion") }

	fileprivate func getInfo(_ str: String) -> String { infoDictionary?[str] as? String ?? "⚠️" }

	public var isTestFlight: Bool {
		return appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
	}
	
	public var isDebug: Bool {
		#if DEBUG
		return true
		#else
		return false
		#endif
	}

	/// The language the app is actually *displaying* in, normalized to a language code (e.g. "es").
	///
	/// Use this — not `Locale.current` — to decide the documentation translation target. A per-app
	/// language override (iOS Settings → Meshtastic → Language) localizes the UI via
	/// `preferredLocalizations` but leaves `Locale.current` reflecting the device's region locale,
	/// so they disagree: the app can be fully Spanish while `Locale.current.language.languageCode`
	/// is still "en". Keying docs translation off the display localization keeps docs in sync with
	/// the chrome the user actually sees. Falls back to "en".
	public var documentationLanguageCode: String {
		let preferred = preferredLocalizations.first ?? "en"
		return Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
	}
}
