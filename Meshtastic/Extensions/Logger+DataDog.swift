//
//  Logger+DataDog.swift
//  Meshtastic
//
//  Created by Jake Bordens on 9/17/25.
//

import Foundation
import os.log
import DatadogRUM
import DatadogLogs
import SwiftUI

enum DataDogLoggableAction {
	// Add more cases as new loggable actions are required.
	case connect(firmwareVersion: String?, transportType: String?, hardwareModel: String?, nodes: Int?, connectionRestored: Bool = false)
	
	var name: String {
		switch self {
		case .connect:
			return "connect"
		}
	}
}

struct DatadogLogger {
	private let osLogger: os.Logger
	private let ddLogger: any DatadogLogs.LoggerProtocol
	
	// Initialize with a subsystem and category, similar to Logger
	fileprivate init(subsystem: String, category: String) {
		self.osLogger = Logger(subsystem: subsystem, category: category)
		self.ddLogger = DatadogLogs.Logger.create(
			with: Logger.Configuration(
				name: "gvh.Meshtastic",
				networkInfoEnabled: true,
				remoteLogThreshold: .debug,
				consoleLogFormat: .short
			)
		)
	}
	
	// ✨ os.Logger functions like debug, info, etc., are not normal functions.
	// They rely on compiler magic to parse the interpolated string, identify the
	// privacy modifiers (.public, .private), and handle the data securely without
	// ever creating a potentially sensitive string in your app's memory.
	// To do this, the compiler must see the string literal at the point of the call.
	// Since this is going to Datadog, care should be taken to only use these functions
	// with public debug data.
	func debug(_ message: String) {
		osLogger.debug("\(message, privacy: .public)")
		ddLogger.debug(message)
	}

	func info(_ message: String) {
		osLogger.info("\(message, privacy: .public)")
		ddLogger.info(message)
	}

	func warning(_ message: String) {
		osLogger.warning("\(message, privacy: .public)")
		ddLogger.warn(message)
	}

	func error(_ message: String) {
		osLogger.error("\(message, privacy: .public)")
		ddLogger.error(message)
	}
	
	// MARK: - Methods for RUM actions
	func action(_ action: DataDogLoggableAction) {
		var attributes = [String: any Encodable]()
		switch action {
		case .connect(let firmwareVersion, let transportType, let hardwareModel, let nodes, let connectionRestored):
			attributes["firmwareVersion"] = firmwareVersion
			attributes["transportType"] = transportType
			attributes["hardwareModel"] = hardwareModel
			attributes["nodes"] = nodes
			if connectionRestored {
				attributes["connectionRestored"] = true
			}
		}
		
		RUMMonitor.shared().addAction(
			type: .custom,
			name: action.name,
			attributes: attributes
		)
	}
}

extension os.Logger {
	static let datadog = DatadogLogger(subsystem: "datadog", category: "🐶 DataDog")
}

/// Decides which of the SDK's auto-detected SwiftUI view names are worth reporting.
///
/// The SDK names a view by reflecting over the hosting controller that is appearing. When the
/// reflection lands on something that is not a screen it reports a name anyway, and that name
/// takes over: the `trackScreen` modifier reports from `onAppear`, the controller reports from
/// `viewDidAppear`, and the later one sits on top of RUM's view stack for as long as the screen
/// is up. That is why every pushed screen was filed under
/// `NavigationStackHostingController<AnyView>` and everything at the app root under `EmptyView`
/// (the root window's controller — the same problem the `FirmwareUpdateGameDemoHost` name had,
/// with a different accidental type), while the screens we had named held the view for a few
/// milliseconds each.
///
/// Returning nil skips the report and leaves the last real screen on top. Names that do identify
/// a screen are passed through unchanged, so screens that reflection already names keep the name
/// they have in Error Tracking.
struct MeshtasticSwiftUIViewsPredicate: SwiftUIRUMViewsPredicate {
	/// Types the reflection reaches that are not screens: SwiftUI value types and preference
	/// keys, our own tracking modifier, and app objects that happen to sit where a view was
	/// expected.
	private static let notScreens: Set<String> = [
		"AnyView",
		"AccessoryManager",
		"EmptyView",
		"EnabledTextSelectability",
		"Font",
		"MeshMapItem",
		"NavigationTitleKey",
		"Never",
		"NodeInfoEntity",
		"PresentationOptionsPreferenceKey",
		"RUMViewModifier",
		"Text",
		"TextAlignment",
		"UUID"
	]

	/// View types the reflection does name, but for screens that now name themselves. Two of
	/// them stood in for more than the screen they are named after: `AppSettings` was reported
	/// for pushes all over the Settings stack, and `DeviceOnboarding` is the sheet the setup
	/// steps live in rather than any one step. Dropping these keeps one name per screen.
	private static let namedElsewhere: Set<String> = [
		"AppSettings",
		"DeviceOnboarding",
		"LoRaConfig",
		"ShareChannels"
	]

	func rumView(for extractedViewName: String) -> RUMView? {
		// A container's own description rather than a name: `NavigationStackHostingController<AnyView>`,
		// `UIHostingController<AnyView>`, or a half-parsed type such as `Text)`.
		guard !extractedViewName.isEmpty,
			  extractedViewName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
			return nil
		}
		// SwiftUI internals (`_PaddingLayout`, `_ViewList_View`) and the SDK's own
		// `AutoTracked_…_Fallback` placeholders.
		guard !extractedViewName.hasPrefix("_"), !extractedViewName.hasPrefix("AutoTracked_") else {
			return nil
		}
		guard !Self.notScreens.contains(extractedViewName),
			  !Self.namedElsewhere.contains(extractedViewName) else {
			return nil
		}
		return RUMView(name: extractedViewName)
	}
}

extension View {
	/// Names this screen for RUM, so crashes and hangs that happen on it are filed under it.
	///
	/// Automatic SwiftUI view tracking names a view by reflecting the hosting controller's
	/// type. The app root is type-erased, so it resolved to the first concrete view type it
	/// found in the root `Group`'s branches — `FirmwareUpdateGameDemoHost`, which is
	/// DEBUG-only and cannot be on screen in a release build. Everything happening at the
	/// root was filed under that name, and the rest landed on
	/// `NavigationStackHostingController<AnyView>`, so nothing could be attributed to a
	/// screen at all.
	///
	/// A name set here only wins while no hosting controller reports over it, which is what
	/// `MeshtasticSwiftUIViewsPredicate` above is for. The names live in `ScreenName` so that no
	/// two screens can share one.
	func trackScreen(_ screen: ScreenName) -> some View {
		trackRUMView(name: screen.rawValue)
	}
}
