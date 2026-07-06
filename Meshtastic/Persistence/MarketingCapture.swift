//
//  MarketingCapture.swift
//  Meshtastic
//
//  DEBUG-only App Store screenshot capture. Paired with the `--meshtastic-marketing-seed` data seed
//  (see PerformanceSeedData / MarketingSeed), this walks a fixed list of screens, snapshots the key
//  window, and writes PNGs into the app sandbox for `scripts/capture-marketing.sh` to pull out.
//
//  Launched with `--marketing-capture`. Zero production impact (whole file is `#if DEBUG`).
//

#if DEBUG
import SwiftUI
import OSLog
import MapKit
import MeshtasticProtobufs

#if canImport(UIKit)
import UIKit
#endif

/// One screen to capture: navigate there, wait for it to settle, snapshot, then optionally tear down.
@MainActor
struct CaptureStep {
	let name: String
	let navigate: () -> Void
	let settle: Duration
	let cleanup: (() -> Void)?
}

@MainActor
enum MarketingCapture {

	/// True when the app was launched to capture marketing screenshots.
	static var isActive: Bool { CommandLine.arguments.contains("--marketing-capture") }

	/// Set by the coordinator just before the map step so `MeshMapMK.frameInitialRegionIfNeeded()` uses
	/// this instead of its normal "fit every node, capped at ~100mi" framing — at that wide a zoom the
	/// seeded mesh's dense downtown anchors all clustered into one bubble with nothing else visible.
	static var pendingMapRegion: MKCoordinateRegion?

	/// Value following a launch flag, e.g. `--marketing-appearance dark` → "dark".
	static func argValue(_ flag: String) -> String? {
		let args = CommandLine.arguments
		guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
		return args[index + 1]
	}

	/// "dark" or "light" from `--marketing-appearance` (default light). Drives both the forced UI style
	/// and the output subfolder, so light/dark is identical across iPhone, iPad, and Mac Catalyst
	/// without depending on `simctl ui appearance` (which doesn't exist for Catalyst).
	static var appearanceName: String {
		argValue("--marketing-appearance")?.lowercased() == "dark" ? "dark" : "light"
	}

	/// Entry point, called once from `ContentView.task`. No-op unless `--marketing-capture` is set.
	/// Assumes the marketing data seed has already run in `MeshtasticAppleApp.init`.
	static func runIfNeeded(router: Router, accessoryManager: AccessoryManager) async {
		guard isActive else { return }
		// Present a connected-radio session so the toolbar shows the green "connected" indicator + node
		// short name (no real radio is attached).
		simulateConnectedNode(accessoryManager)
		// Force the requested appearance (and, on Mac Catalyst, a fixed window size) so the capture is
		// deterministic across platforms.
		applyAppearanceAndWindowSize()
		Logger.data.info("📸 [Marketing] Capture starting (\(appearanceName, privacy: .public))")
		// Let the first frame (appearance/size change + the seeded @Query views) settle first.
		try? await Task.sleep(for: .milliseconds(2200))

		for step in makeSteps(router: router) {
			step.navigate()
			try? await Task.sleep(for: step.settle)
			if let image = snapshotKeyWindow() {
				writePNG(image, name: step.name)
				Logger.data.info("📸 [Marketing] Captured \(step.name, privacy: .public)")
			} else {
				Logger.data.error("📸 [Marketing] Failed to snapshot \(step.name, privacy: .public)")
			}
			step.cleanup?()
			try? await Task.sleep(for: .milliseconds(500)) // let any pop/dismiss animation finish
		}

		Logger.data.info("📸 [Marketing] Capture complete — exiting")
		try? await Task.sleep(for: .milliseconds(300))
		exit(0)
	}

	// MARK: Steps

	/// iPad and Mac Catalyst show node list + node detail together in a split view, so the standalone
	/// node-list shot is redundant there — node-detail alone already conveys both. iPhone still needs
	/// it since the two are separate screens there.
	private static var capturesNodeListSeparately: Bool {
#if targetEnvironment(macCatalyst)
		return false
#elseif canImport(UIKit)
		return UIDevice.current.userInterfaceIdiom != .pad
#else
		return true
#endif
	}

	/// Full-screen screens, root-level views captured before pushed views that share a NavigationStack.
	/// Capped at 5 screens (10 shots at light+dark) to match the App Store's per-device-size limit —
	/// iPad/Mac drop node-list (see `capturesNodeListSeparately`), landing at 4 screens / 8 shots there.
	private static func makeSteps(router: Router) -> [CaptureStep] {
		let nodeDetailNum = MarketingSeed.nodeNum(for: 4)  // U-District Solar (a favorite, rich telemetry)

		var steps: [CaptureStep] = []

		if capturesNodeListSeparately {
			steps.append(CaptureStep(name: "01-nodes", navigate: {
				router.popToRoot(tab: .nodes)
				router.selectedNodeNum = nil
				router.selectedTab = .nodes
			}, settle: .milliseconds(2200), cleanup: nil))
		}

		steps.append(CaptureStep(name: "02-map", navigate: {
			// A tighter frame than "fit everything" — see `pendingMapRegion`'s doc comment.
			pendingMapRegion = MKCoordinateRegion(
				center: CLLocationCoordinate2D(latitude: 47.6100, longitude: -122.2900),
				span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.30)
			)
			router.mapState = nil
			router.selectedTab = .map
		}, settle: .milliseconds(4500), cleanup: {
			pendingMapRegion = nil
		})) // MapKit needs time to frame + load tiles

		steps.append(CaptureStep(name: "03-node-detail", navigate: {
			router.navigateToNodeDetail(nodeNum: nodeDetailNum)
		}, settle: .milliseconds(2800), cleanup: {
			router.selectedNodeNum = nil
		}))

		// One messaging shot (channel — livelier for marketing than a 1:1 DM), not two.
		steps.append(CaptureStep(name: "04-messages", navigate: {
			router.selectedTab = .messages
			router.messagesSection = .channels()
			router.messagesState = .channels(channelId: 0)
		}, settle: .milliseconds(2800), cleanup: {
			router.popToRoot(tab: .messages)
		}))

		// Discovery, not Settings — the newer mesh-beacon discovery feature sells better than a
		// generic settings list.
		steps.append(CaptureStep(name: "05-discovery", navigate: {
			router.selectedTab = .settings
			router.settingsPath = [.localMeshDiscovery]
		}, settle: .milliseconds(2800), cleanup: {
			router.settingsPath = []
		}))

		return steps
	}

	/// Populate `AccessoryManager` with a fake connected session (the seeded local node), so every
	/// screen's toolbar shows the green "connected" indicator with the node's short name. The stub
	/// connection is never driven — capture only reads `activeConnection.device` for display.
	static func simulateConnectedNode(_ accessoryManager: AccessoryManager) {
		let baseNodeNum: Int64 = 0x0A00_0000
		var device = Device(id: UUID(), name: MarketingSeed.anchors[0].long, transportType: .ble,
							identifier: "marketing-capture", connectionState: .connected, num: baseNodeNum)
		device.shortName = MarketingSeed.anchors[0].short
		device.longName = MarketingSeed.anchors[0].long
		accessoryManager.activeConnection = (device, MarketingStubConnection())
		accessoryManager.activeDeviceNum = baseNodeNum
		accessoryManager.isConnected = true
	}

	// MARK: Window snapshot + output

#if canImport(UIKit)
	private static var keyWindow: UIWindow? {
		let windows = UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
		return windows.first { $0.isKeyWindow } ?? windows.first
	}

	static func snapshotKeyWindow() -> UIImage? {
		guard let window = keyWindow else { return nil }
		let format = UIGraphicsImageRendererFormat()
		format.scale = window.screen.scale
		let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
		return renderer.image { _ in
			window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
		}
	}

	/// Force the requested light/dark style on the key window, and on Mac Catalyst pin the window to the
	/// `--marketing-size WxH` (points) so the shot matches a target Mac screen (e.g. MacBook Air).
	static func applyAppearanceAndWindowSize() {
		guard let window = keyWindow else { return }
		window.overrideUserInterfaceStyle = appearanceName == "dark" ? .dark : .light
#if targetEnvironment(macCatalyst)
		if let spec = argValue("--marketing-size"), let scene = window.windowScene {
			let parts = spec.lowercased().split(separator: "x")
			if parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) {
				let size = CGSize(width: width, height: height)
				scene.sizeRestrictions?.minimumSize = size
				scene.sizeRestrictions?.maximumSize = size
			}
		}
#endif
	}

	static func writePNG(_ image: UIImage, name: String, subfolder: String = "") {
		guard let data = image.pngData() else { return }
		var directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("marketing")
			.appendingPathComponent(appearanceName)
		if !subfolder.isEmpty { directory = directory.appendingPathComponent(subfolder) }
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try? data.write(to: directory.appendingPathComponent("\(name).png"))
	}
#else
	static func snapshotKeyWindow() -> Any? { nil }
	static func applyAppearanceAndWindowSize() {}
	static func writePNG(_ image: Any, name: String, subfolder: String = "") {}
#endif
}

/// A no-op `Connection` used only to populate `AccessoryManager.activeConnection` during marketing
/// capture. Its methods are never invoked — the capture neither sends nor receives.
actor MarketingStubConnection: Connection {
	nonisolated let type: TransportType = .ble
	var isConnected: Bool = true
	func send(_ data: ToRadio) async throws {}
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {}
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}
#endif
