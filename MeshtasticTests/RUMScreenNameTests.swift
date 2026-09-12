//
//  RUMScreenNameTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/12/26.
//

import Testing
import DatadogRUM
@testable import Meshtastic

/// The predicate decides what a crash or hang gets filed under, so the cases it has to reject are
/// worth pinning down. Every rejected name here was a real bucket in RUM.
@Suite("RUM screen names")
struct RUMScreenNameTests {
	private let predicate = MeshtasticSwiftUIViewsPredicate()

	@Test("A view type the reflection resolved is reported under its own name")
	func keepsRealScreenNames() {
		for name in ["TraceRouteLog", "DeviceMetricsLog", "NodeListFilter", "MapSettingsForm", "DeviceOnboarding"] {
			#expect(predicate.rumView(for: name)?.name == name)
		}
	}

	@Test("A hosting controller's own description is not a screen")
	func dropsContainerDescriptions() {
		for name in ["NavigationStackHostingController<AnyView>", "UIHostingController<AnyView>", "Text)"] {
			#expect(predicate.rumView(for: name) == nil)
		}
	}

	@Test("SwiftUI internals and the SDK's placeholders are not screens")
	func dropsInternals() {
		for name in ["_PaddingLayout", "_ViewList_View", "AutoTracked_HostingController_Fallback"] {
			#expect(predicate.rumView(for: name) == nil)
		}
	}

	@Test("EmptyView, the app root's reflected type, is not a screen")
	func dropsAppRoot() {
		#expect(predicate.rumView(for: "EmptyView") == nil)
	}

	@Test("Screens that name themselves are not also reported under a reflected name")
	func dropsNamesSetElsewhere() {
		for name in ["AppSettings", "LoRaConfig", "ShareChannels"] {
			#expect(predicate.rumView(for: name) == nil)
		}
	}

	/// Swift already rejects a duplicate raw value, so this can only fail if `ScreenName` stops
	/// being the single source of names. It is here to say that out loud.
	@Test("No two screens share a name")
	func namesAreUnique() {
		let names = ScreenName.allCases.map(\.rawValue)
		#expect(Set(names).count == names.count)
	}

	@Test("Every name reads as a name, not as a type")
	func namesAreReadable() {
		for name in ScreenName.allCases.map(\.rawValue) {
			#expect(!name.isEmpty)
			#expect(name.trimmingCharacters(in: .whitespaces) == name)
			#expect(!name.contains(where: { "_<>().".contains($0) }), "\(name) looks like a type description")
		}
	}

	@Test("Every settings destination resolves to a name")
	func settingsDestinationsAreNamed() {
		let destinations: [SettingsNavigationState] = [
			.about, .appSettings, .routes, .routeRecorder, .lora, .channels, .shareQRCode, .user,
			.bluetooth, .device, .display, .network, .position, .power, .ambientLighting, .audio,
			.cannedMessages, .detectionSensor, .meshBeacon, .externalNotification, .mqtt,
			.neighborInfo, .rangeTest, .paxCounter, .ringtone, .serial, .security, .storeAndForward,
			.telemetry, .trafficManagement, .debugLogs, .traceRoutes, .appFiles, .firmwareUpdates,
			.deviceLinks, .tak, .takConfig, .tools, .coreDataBrowser, .localMeshDiscovery,
			.helpDocs, .backupManagement
		]
		let names = destinations.map(\.screenName)
		#expect(Set(names).count == names.count)
	}
}
