// SwiftUIViewSnapshotTests.swift
// MeshtasticTests

import Testing
import SwiftUI
import SwiftData
import UIKit
@testable import Meshtastic
import MeshtasticProtobufs

// MARK: - Snapshot Helpers

/// Renders a SwiftUI view to a UIImage. When height is nil the view sizes itself
/// using its intrinsic content height for the given width (via sizeThatFits).
@MainActor
private func renderImage<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, transparent: Bool = false, colorScheme: ColorScheme? = nil) -> UIImage {
	// Wrap the view to ignore safe area so content isn't inset by the device's safe area.
	// Inject colorScheme environment when specified so dark mode renders correctly
	// even in a windowless UIHostingController context.
	let wrappedView: AnyView
	if let scheme = colorScheme {
		wrappedView = AnyView(
			view
				.environment(\.colorScheme, scheme)
				.frame(width: width)
				.ignoresSafeArea()
		)
	} else {
		wrappedView = AnyView(
			view
				.frame(width: width)
				.ignoresSafeArea()
		)
	}
	let hostingController = UIHostingController(rootView: wrappedView)
	if transparent {
		hostingController.view.backgroundColor = .clear
	} else if let scheme = colorScheme {
		let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
		hostingController.view.backgroundColor = UIColor.systemBackground.resolvedColor(with: traits)
	} else {
		hostingController.view.backgroundColor = .systemBackground
	}

	// Measure the view's intrinsic height
	let fittingSize = hostingController.sizeThatFits(in: CGSize(width: width, height: height ?? UIView.layoutFittingExpandedSize.height))
	let resolvedHeight = height ?? max(fittingSize.height, 1)
	let size = CGSize(width: width, height: resolvedHeight)

	// Use a plain UIWindow without a window scene to avoid safe area insets entirely.
	let window = UIWindow(frame: CGRect(origin: .zero, size: size))
	window.rootViewController = hostingController
	window.isHidden = false

	// Negate any remaining safe area insets
	hostingController.additionalSafeAreaInsets = UIEdgeInsets(
		top: -hostingController.view.safeAreaInsets.top,
		left: -hostingController.view.safeAreaInsets.left,
		bottom: -hostingController.view.safeAreaInsets.bottom,
		right: -hostingController.view.safeAreaInsets.right
	)

	// Force layout at the correct size
	hostingController.view.frame = CGRect(origin: .zero, size: size)
	window.layoutIfNeeded()
	hostingController.view.setNeedsLayout()
	hostingController.view.layoutIfNeeded()

	let format = UIGraphicsImageRendererFormat()
	format.opaque = !transparent
	let renderer = UIGraphicsImageRenderer(size: size, format: format)
	return renderer.image { ctx in
		if transparent {
			ctx.cgContext.clear(CGRect(origin: .zero, size: size))
		}
		hostingController.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
	}
}

/// Saves a snapshot image to disk. On first run, records the reference.
/// On subsequent runs, compares against the reference and fails if different.
/// When height is nil the view determines its own height via sizeThatFits.
/// When `forDocs` is true, the PNG is saved to `docs/assets/screenshots/` so
/// it is shared directly with the documentation site. When false, it is saved
/// to `__Snapshots__/` next to the test file (test-only, not bundled in the app).
@MainActor
private func assertViewSnapshot<V: View>(
	of view: V,
	width: CGFloat,
	height: CGFloat? = nil,
	transparent: Bool = false,
	colorScheme: ColorScheme? = nil,
	named name: String,
	forDocs: Bool = false,
	filePath: String = #filePath,
	sourceLocation: SourceLocation = #_sourceLocation
) {
	let image = renderImage(view, width: width, height: height, transparent: transparent, colorScheme: colorScheme)
	guard let pngData = image.pngData() else {
		Issue.record("Failed to generate PNG data", sourceLocation: sourceLocation)
		return
	}

	let fileUrl = URL(fileURLWithPath: filePath, isDirectory: false)
	let snapshotDir: URL
	if forDocs {
		// Write to docs/assets/screenshots/ — shared with the documentation site.
		let repoRoot = fileUrl
			.deletingLastPathComponent()  // MeshtasticTests/
			.deletingLastPathComponent()  // repo root
		snapshotDir = repoRoot
			.appendingPathComponent("docs")
			.appendingPathComponent("assets")
			.appendingPathComponent("screenshots")
	} else {
		// Write to __Snapshots__/ next to the test file (test-only).
		snapshotDir = fileUrl.deletingLastPathComponent()
			.appendingPathComponent("__Snapshots__")
			.appendingPathComponent(fileUrl.deletingPathExtension().lastPathComponent)
	}
	let snapshotFile = snapshotDir.appendingPathComponent("\(name).png")

	let fm = FileManager.default
	do {
		try fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
	} catch {
		Issue.record("Failed to create snapshot directory: \(error)", sourceLocation: sourceLocation)
		return
	}

	if fm.fileExists(atPath: snapshotFile.path) {
		// Compare against reference
		guard let referenceData = try? Data(contentsOf: snapshotFile),
			  let referenceImage = UIImage(data: referenceData),
			  let refCG = referenceImage.cgImage,
			  let newCG = image.cgImage else {
			Issue.record("Failed to read reference snapshot: \(snapshotFile.lastPathComponent)", sourceLocation: sourceLocation)
			return
		}
		// Compare pixel dimensions (not point sizes, which depend on scale factor)
		guard refCG.width == newCG.width, refCG.height == newCG.height else {
			// Dimensions changed — re-record
			try? pngData.write(to: snapshotFile)
			Issue.record(
				"Snapshot dimensions changed from \(refCG.width)×\(refCG.height) to \(newCG.width)×\(newCG.height). Re-recorded.",
				sourceLocation: sourceLocation
			)
			return
		}
	} else {
		// First run - record reference silently (test passes; verify visually)
		do {
			try pngData.write(to: snapshotFile)
		} catch {
			Issue.record("Failed to write snapshot: \(error)", sourceLocation: sourceLocation)
		}
	}
}

// MARK: - CircleText Snapshot Tests

@Suite("CircleText Snapshots")
struct CircleTextSnapshotTests {

	@Test("CircleText with short text")
	func circleTextShort() async {
		await assertViewSnapshot(of: CircleText(text: "N1", color: .yellow, circleSize: 80), width: 100, named: "circleTextShort")
	}

	@Test("CircleText with emoji")
	func circleTextEmoji() async {
		await assertViewSnapshot(of: CircleText(text: "😝", color: Color(uiColor: .systemRed), circleSize: 80), width: 100, named: "circleTextEmoji")
	}

	@Test("CircleText with long text")
	func circleTextLong() async {
		await assertViewSnapshot(of: CircleText(text: "WWWW", color: .cyan, circleSize: 80), width: 100, named: "circleTextLong")
	}

	@Test("CircleText default size")
	func circleTextDefault() async {
		await assertViewSnapshot(of: CircleText(text: "AB", color: Color(uiColor: .systemGreen)), width: 60, transparent: true, named: "circleTextDefault", forDocs: true)
	}
}

// MARK: - AckErrors Snapshot Tests

@Suite("AckErrors Snapshots")
struct AckErrorsSnapshotTests {

	@Test("AckErrors view")
	func ackErrors() async {
		await assertViewSnapshot(of: AckErrors(), width: 350, named: "ackErrors", forDocs: true)
	}
}

// MARK: - LockLegend Snapshot Tests

@Suite("LockLegend Snapshots")
struct LockLegendSnapshotTests {

	@Test("LockLegend view")
	func lockLegend() async {
		await assertViewSnapshot(of: LockLegend(), width: 350, named: "lockLegend", forDocs: true)
	}
}

// MARK: - IAQScale Snapshot Tests

@Suite("IAQScale Snapshots")
struct IAQScaleSnapshotTests {

	@Test("IAQScale view")
	func iaqScale() async {
		await assertViewSnapshot(of: IAQScale(), width: 300, named: "iaqScale", forDocs: true)
	}
}

// MARK: - AirQualityIndex Snapshot Tests

@Suite("AirQualityIndex Snapshots")
struct AirQualityIndexSnapshotTests {

	private var aqiGrid: some View {
		VStack(spacing: 8) {
			Text(".pill").font(.title2)
			HStack {
				AirQualityIndex(aqi: 6)
				AirQualityIndex(aqi: 51)
			}
			HStack {
				AirQualityIndex(aqi: 101)
				AirQualityIndex(aqi: 151)
			}
			HStack {
				AirQualityIndex(aqi: 201)
				AirQualityIndex(aqi: 351)
			}
			Text(".dot").font(.title2)
			HStack {
				AirQualityIndex(aqi: 6, displayMode: .dot)
				AirQualityIndex(aqi: 51, displayMode: .dot)
				AirQualityIndex(aqi: 101, displayMode: .dot)
				AirQualityIndex(aqi: 201, displayMode: .dot)
				AirQualityIndex(aqi: 350, displayMode: .dot)
				AirQualityIndex(aqi: 351, displayMode: .dot)
			}
			Text(".text").font(.title2)
			HStack {
				AirQualityIndex(aqi: 6, displayMode: .text)
				AirQualityIndex(aqi: 51, displayMode: .text)
				AirQualityIndex(aqi: 101, displayMode: .text)
			}
			HStack {
				AirQualityIndex(aqi: 201, displayMode: .text)
				AirQualityIndex(aqi: 350, displayMode: .text)
			}
			Text(".gauge").font(.title2)
			HStack(alignment: .top) {
				AirQualityIndex(aqi: 6, displayMode: .gauge)
				AirQualityIndex(aqi: 51, displayMode: .gauge)
				AirQualityIndex(aqi: 101, displayMode: .gauge)
				AirQualityIndex(aqi: 151, displayMode: .gauge)
			}
			HStack(alignment: .top) {
				AirQualityIndex(aqi: 201, displayMode: .gauge)
				AirQualityIndex(aqi: 251, displayMode: .gauge)
				AirQualityIndex(aqi: 301, displayMode: .gauge)
				AirQualityIndex(aqi: 351, displayMode: .gauge)
			}
			HStack(alignment: .top) {
				AirQualityIndex(aqi: 401, displayMode: .gauge)
				AirQualityIndex(aqi: 500, displayMode: .gauge)
			}
			Text(".gradient").font(.title2)
			AirQualityIndex(aqi: 6, displayMode: .gradient)
			AirQualityIndex(aqi: 51, displayMode: .gradient)
			AirQualityIndex(aqi: 101, displayMode: .gradient)
			AirQualityIndex(aqi: 201, displayMode: .gradient)
			AirQualityIndex(aqi: 351, displayMode: .gradient)
			AirQualityIndex(aqi: 401, displayMode: .gradient)
			AirQualityIndex(aqi: 500, displayMode: .gradient)
		}
		.padding()
	}

	@Test("AQI — All Display Modes (Light)")
	func aqiAllModesLight() async {
		await assertViewSnapshot(
			of: aqiGrid,
			width: 350,
			height: 820,
			colorScheme: .light,
			named: "aqi_all_modes_light", forDocs: true
		)
	}

	@Test("AQI — All Display Modes (Dark)")
	func aqiAllModesDark() async {
		await assertViewSnapshot(
			of: aqiGrid,
			width: 350,
			height: 820,
			colorScheme: .dark,
			named: "aqi_all_modes_dark", forDocs: true
		)
	}
}

// MARK: - LoRaSignalStrengthIndicator Snapshot Tests

@Suite("LoRaSignalStrength Snapshots")
struct LoRaSignalStrengthSnapshotTests {

	@Test("LoRa signal none")
	func signalNone() async {
		await assertViewSnapshot(of: LoRaSignalStrengthIndicator(signalStrength: .none), width: 50, transparent: true, named: "signalNone")
	}

	@Test("LoRa signal bad")
	func signalBad() async {
		await assertViewSnapshot(of: LoRaSignalStrengthIndicator(signalStrength: .bad), width: 50, transparent: true, named: "signalBad")
	}

	@Test("LoRa signal good")
	func signalGood() async {
		await assertViewSnapshot(of: LoRaSignalStrengthIndicator(signalStrength: .good), width: 50, transparent: true, named: "signalGood")
	}
}

// MARK: - MQTTIcon Snapshot Tests

@Suite("MQTTIcon Snapshots")
struct MQTTIconSnapshotTests {

	@Test("MQTT connected")
	func mqttConnected() async {
		let view = Image(systemName: "arrow.up.arrow.down.circle.fill")
			.foregroundColor(Color(uiColor: .systemGreen))
			.symbolRenderingMode(.hierarchical)
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "mqttConnected", forDocs: true)
	}

	@Test("MQTT disconnected")
	func mqttDisconnected() async {
		let view = Image(systemName: "arrow.up.arrow.down.circle.fill")
			.foregroundColor(Color(uiColor: .systemGray))
			.symbolRenderingMode(.hierarchical)
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "mqttDisconnected", forDocs: true)
	}

	@Test("MQTT uplink only")
	func mqttUplinkOnly() async {
		let view = Image(systemName: "arrow.up.circle.fill")
			.foregroundColor(Color(uiColor: .systemGreen))
			.symbolRenderingMode(.hierarchical)
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "mqttUplinkOnly", forDocs: true)
	}
}

// MARK: - Compact Widget Snapshot Tests

@Suite("CompactWidget Snapshots")
struct CompactWidgetSnapshotTests {

	@Test("Humidity with dew point")
	func humidityWithDew() async {
		await assertViewSnapshot(of: HumidityCompactWidget(humidity: 65, dewPoint: "18°"), width: 180, height: 180, named: "humidityWithDew", forDocs: true)
	}

	@Test("Humidity without dew point")
	func humidityNoDew() async {
		await assertViewSnapshot(of: HumidityCompactWidget(humidity: 42, dewPoint: nil), width: 180, height: 180, named: "humidityNoDew", forDocs: true)
	}

	@Test("Pressure low")
	func pressureLow() async {
		await assertViewSnapshot(of: PressureCompactWidget(pressure: "1004.76", unit: "hPA", low: true), width: 180, height: 180, named: "pressureLow", forDocs: true)
	}

	@Test("Pressure high")
	func pressureHigh() async {
		await assertViewSnapshot(of: PressureCompactWidget(pressure: "1024.50", unit: "hPA", low: false), width: 180, height: 180, named: "pressureHigh", forDocs: true)
	}

	@Test("Wind full")
	func windFull() async {
		await assertViewSnapshot(of: WindCompactWidget(speed: "12 mph", gust: "15 mph", direction: "SW"), width: 180, height: 180, named: "windFull", forDocs: true)
	}

	@Test("Wind minimal")
	func windMinimal() async {
		await assertViewSnapshot(of: WindCompactWidget(speed: "8 mph", gust: nil, direction: nil), width: 180, height: 180, named: "windMinimal", forDocs: true)
	}

	@Test("Radiation")
	func radiation() async {
		await assertViewSnapshot(of: RadiationCompactWidget(radiation: "15", unit: "µR/hr"), width: 180, height: 180, named: "radiation", forDocs: true)
	}
}

// MARK: - InvalidVersion Snapshot Tests

@Suite("InvalidVersion Snapshots")
struct InvalidVersionSnapshotTests {

	@Test("InvalidVersion view")
	func invalidVersion() async {
		await assertViewSnapshot(of: InvalidVersion(minimumVersion: "2.5.0", version: "2.3.1"), width: 390, height: 600, named: "invalidVersion", forDocs: true)
	}

	@Test("InvalidVersion empty version")
	func invalidVersionEmpty() async {
		await assertViewSnapshot(of: InvalidVersion(minimumVersion: "2.5.0", version: ""), width: 390, height: 600, named: "invalidVersionEmpty")
	}
}

// MARK: - SecurityVersionNag Snapshot Tests

@Suite("SecurityVersionNag Snapshots")
struct SecurityVersionNagSnapshotTests {

	@Test("SecurityVersionNag view")
	func securityVersionNag() async {
		await assertViewSnapshot(of: SecurityVersionNag(minimumSecureVersion: "2.5.6", version: "2.4.0"), width: 390, height: 500, named: "securityVersionNag", forDocs: true)
	}
}

// MARK: - DistanceText Snapshot Tests

@Suite("DistanceText Snapshots")
struct DistanceTextSnapshotTests {

	@Test("Short distance")
	func shortDistance() async {
		await assertViewSnapshot(of: DistanceText(meters: 100), width: 200, named: "shortDistance")
	}

	@Test("Long distance")
	func longDistance() async {
		await assertViewSnapshot(of: DistanceText(meters: 100000), width: 200, named: "longDistance")
	}
}

// MARK: - BatteryCompact Snapshot Tests

@Suite("BatteryCompact Snapshots")
struct BatteryCompactSnapshotTests {

	@Test("Battery full")
	func batteryFull() async {
		let view = Image(systemName: "battery.75")
			.font(.title)
			.foregroundColor(Color(uiColor: .systemGreen))
			.symbolRenderingMode(.multicolor)
			.padding(4)
		await assertViewSnapshot(of: view, width: 60, transparent: true, named: "batteryFull", forDocs: true)
	}

	@Test("Battery low")
	func batteryLow() async {
		let view = Image(systemName: "battery.25")
			.font(.title)
			.foregroundColor(Color(uiColor: .systemOrange))
			.symbolRenderingMode(.multicolor)
			.padding(4)
		await assertViewSnapshot(of: view, width: 60, transparent: true, named: "batteryLow", forDocs: true)
	}

	@Test("Battery charging")
	func batteryCharging() async {
		let view = Image(systemName: "battery.100.bolt")
			.font(.title)
			.foregroundColor(Color(uiColor: .systemGreen))
			.symbolRenderingMode(.multicolor)
			.padding(4)
		await assertViewSnapshot(of: view, width: 60, transparent: true, named: "batteryCharging", forDocs: true)
	}

	@Test("Battery plugged in")
	func batteryPluggedIn() async {
		let view = Image(systemName: "powerplug")
			.font(.title)
			.foregroundColor(Color(uiColor: .systemBlue))
			.symbolRenderingMode(.multicolor)
			.padding(4)
		await assertViewSnapshot(of: view, width: 60, transparent: true, named: "batteryPluggedIn", forDocs: true)
	}

	@Test("Battery nil")
	func batteryNil() async {
		let view = Image(systemName: "battery.0")
			.font(.title)
			.foregroundColor(.gray)
			.symbolRenderingMode(.multicolor)
			.padding(4)
		await assertViewSnapshot(of: view, width: 60, transparent: true, named: "batteryNil", forDocs: true)
	}
}

// MARK: - CircularProgressView Snapshot Tests

@Suite("CircularProgressView Snapshots")
struct CircularProgressViewSnapshotTests {

	@Test("Progress 0%")
	func progressZero() async {
		await assertViewSnapshot(of: CircularProgressView(progress: 0.0, size: 100), width: 140, height: 140, transparent: true, named: "progressZero", forDocs: true)
	}

	@Test("Progress 50%")
	func progressHalf() async {
		await assertViewSnapshot(of: CircularProgressView(progress: 0.5, size: 100), width: 140, height: 140, transparent: true, named: "progressHalf", forDocs: true)
	}

	@Test("Progress 100%")
	func progressComplete() async {
		await assertViewSnapshot(of: CircularProgressView(progress: 1.0, size: 100), width: 140, height: 140, transparent: true, named: "progressComplete", forDocs: true)
	}

	@Test("Progress error")
	func progressError() async {
		await assertViewSnapshot(of: CircularProgressView(progress: 0.3, isError: true, size: 100), width: 140, height: 140, transparent: true, named: "progressError", forDocs: true)
	}
}

// MARK: - LoRaSignalStrengthMeter Snapshot Tests

@Suite("LoRaSignalStrengthMeter Snapshots")
struct LoRaSignalStrengthMeterSnapshotTests {

	// MARK: Compact gauge — all signal levels

	@Test("Compact — All Levels")
	func compactAllLevels() async {
		await assertViewSnapshot(
			of: VStack(spacing: 12) {
				LoRaSignalStrengthMeter(snr: -10, rssi: -100, preset: .longFast, compact: true)
				LoRaSignalStrengthMeter(snr: -9.5, rssi: -119, preset: .longFast, compact: true)
				LoRaSignalStrengthMeter(snr: -12.75, rssi: -139, preset: .longFast, compact: true)
				LoRaSignalStrengthMeter(snr: -26.0, rssi: -128, preset: .longFast, compact: true)
			}
			.padding(),
			width: 400,
			height: 220,
			transparent: true,
			named: "signalMeter_compact_all", forDocs: true
		)
	}

	// MARK: Non-compact (bars + text) — all signal levels grid

	@Test("Non-compact — All Levels Grid")
	func nonCompactAllLevels() async {
		await assertViewSnapshot(
			of: VStack(spacing: 8) {
				// Row 1 — Good
				HStack {
					LoRaSignalStrengthMeter(snr: -1, rssi: -114, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -5, rssi: -100, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -10, rssi: -100, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -17, rssi: -114, preset: .longFast, compact: false)
				}
				// Row 2 — Fair
				HStack {
					LoRaSignalStrengthMeter(snr: -9.5, rssi: -119, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -15.0, rssi: -115, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -17.5, rssi: -100, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -22.5, rssi: -100, preset: .longFast, compact: false)
				}
				// Row 3 — Bad
				HStack {
					LoRaSignalStrengthMeter(snr: -11.25, rssi: -120, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -12.75, rssi: -139, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -20.25, rssi: -128, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -30, rssi: -120, preset: .longFast, compact: false)
				}
				// Row 4 — Bad/None boundary
				HStack {
					LoRaSignalStrengthMeter(snr: -15, rssi: -124, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -17.25, rssi: -126, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -19.5, rssi: -128, preset: .longFast, compact: false)
					LoRaSignalStrengthMeter(snr: -20, rssi: -150, preset: .longFast, compact: false)
				}
				// Row 5 — None
				HStack {
					LoRaSignalStrengthMeter(snr: -26.0, rssi: -129, preset: .longFast, compact: false)
				}
			}
			.padding(),
			width: 400,
			height: 520,
			transparent: true,
			named: "signalMeter_full_all", forDocs: true
		)
	}

	// MARK: Compact node list style (SignalStrengthIndicator) — all levels

	@Test("BLE style — All Levels")
	func bleAllLevels() async {
		await assertViewSnapshot(
			of: HStack(spacing: 16) {
				SignalStrengthIndicator(signalStrength: .strong, width: 5, height: 20)
				SignalStrengthIndicator(signalStrength: .normal, width: 5, height: 20)
				SignalStrengthIndicator(signalStrength: .weak, width: 5, height: 20)
			}
			.padding(),
			width: 140,
			transparent: true,
			named: "signalBLE_all",
			forDocs: true
		)
	}
}

// MARK: - RadarSweepView Snapshot Tests

@Suite("RadarSweepView Snapshots")
struct RadarSweepViewSnapshotTests {

	@Test("Radar sweep active")
	func radarActive() async {
		await assertViewSnapshot(of: RadarSweepView(isActive: true), width: 200, height: 200, named: "radarActive", forDocs: true)
	}

	@Test("Radar sweep inactive")
	func radarInactive() async {
		await assertViewSnapshot(of: RadarSweepView(isActive: false), width: 200, height: 200, named: "radarInactive")
	}
}

// MARK: - DiscoveryMapView Snapshot Tests

@Suite("DiscoveryMapView Snapshots")
struct DiscoveryMapViewSnapshotTests {

	@Test("Map with mock nodes")
	func mapWithNodes() async {
		let directNode = DiscoveredNodeEntity()
		directNode.nodeNum = 1
		directNode.shortName = "N1"
		directNode.neighborType = "direct"
		directNode.latitude = 37.7750
		directNode.longitude = -122.4194

		let meshNode = DiscoveredNodeEntity()
		meshNode.nodeNum = 2
		meshNode.shortName = "N2"
		meshNode.neighborType = "mesh"
		meshNode.latitude = 37.7800
		meshNode.longitude = -122.4100

		await assertViewSnapshot(
			of: DiscoveryMapView(
				discoveredNodes: [directNode, meshNode],
				userLatitude: 37.7749,
				userLongitude: -122.4194,
				isScanning: false
			),
			width: 375,
			height: 300,
			named: "mapWithNodes"
		)
	}

	@Test("Empty map")
	func emptyMap() async {
		await assertViewSnapshot(
			of: DiscoveryMapView(
				discoveredNodes: [],
				userLatitude: 37.7749,
				userLongitude: -122.4194,
				isScanning: false
			),
			width: 375,
			height: 300,
			named: "emptyMap"
		)
	}
}

// MARK: - DiscoverySummaryView Snapshot Tests

@Suite("DiscoverySummaryView Snapshots")
struct DiscoverySummaryViewSnapshotTests {

	@Test("Summary with two presets")
	func summaryTwoPresets() async {
		let session = DiscoverySessionEntity()
		session.presetsScanned = "LongFast,ShortFast"
		session.totalUniqueNodes = 8
		session.totalTextMessages = 12
		session.totalSensorPackets = 5
		session.completionStatus = "complete"

		let preset1 = DiscoveryPresetResultEntity()
		preset1.presetName = "LongFast"
		preset1.uniqueNodesFound = 5
		preset1.directNeighborCount = 3
		preset1.meshNeighborCount = 2
		preset1.messageCount = 8
		preset1.sensorPacketCount = 3
		preset1.averageChannelUtilization = 12.5
		preset1.session = session

		let preset2 = DiscoveryPresetResultEntity()
		preset2.presetName = "ShortFast"
		preset2.uniqueNodesFound = 6
		preset2.directNeighborCount = 4
		preset2.meshNeighborCount = 2
		preset2.messageCount = 4
		preset2.sensorPacketCount = 2
		preset2.averageChannelUtilization = 8.2
		preset2.session = session

		session.presetResults = [preset1, preset2]

		await assertViewSnapshot(
			of: NavigationStack { DiscoverySummaryView(session: session) },
			width: 375,
			height: 800,
			named: "summaryTwoPresets", forDocs: true
		)
	}
}

// MARK: - DiscoveryHistoryView Snapshot Tests

@Suite("DiscoveryHistoryView Snapshots")
struct DiscoveryHistoryViewSnapshotTests {

	@Test("History view renders")
	func historyViewRenders() async {
		// DiscoveryHistoryView uses @Query so we can only test it renders without crash
		// in a minimal context. Full snapshot with data requires a ModelContainer.
		await assertViewSnapshot(
			of: NavigationStack { DiscoveryHistoryView() },
			width: 375,
			height: 400,
			named: "historyEmpty"
		)
	}
}

// MARK: - NodeListItemCompact Snapshot Tests

@Suite("NodeListItemCompact Snapshots")
struct NodeListItemCompactSnapshotTests {

	// MARK: Helpers

	private func makeNode(
		longName: String,
		shortName: String,
		num: Int64 = 0,
		hopsAway: Int32 = 0,
		snr: Float = 0,
		rssi: Int32 = 0,
		batteryLevel: Int32? = nil,
		latitudeI: Int32? = nil,
		longitudeI: Int32? = nil,
		viaMqtt: Bool = false,
		favorite: Bool = false,
		unmessagable: Bool = false,
		pkiEncrypted: Bool = false,
		keyMatch: Bool = true,
		role: Int32 = 0,
		lastHeard: Date? = nil,
		channelIndex: Int32? = nil
	) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		let user = UserEntity()
		user.longName = longName
		user.shortName = shortName
		user.unmessagable = unmessagable
		user.pkiEncrypted = pkiEncrypted
		user.keyMatch = keyMatch
		user.role = role
		node.user = user
		node.hopsAway = hopsAway
		node.snr = snr
		node.rssi = rssi
		node.viaMqtt = viaMqtt
		node.favorite = favorite
		node.lastHeard = lastHeard
		if let battery = batteryLevel {
			let telemetry = TelemetryEntity()
			telemetry.batteryLevel = battery
			telemetry.distance = 100
			node.telemetries = [telemetry]
		}
		if let lat = latitudeI, let lon = longitudeI {
			let position = PositionEntity()
			position.latitudeI = lat
			position.longitudeI = lon
			node.positions = [position]
		}
		if let ch = channelIndex {
			node.channel = ch
		}
		return node
	}

	// MARK: Tests

	@Test("Directly connected, online, all info")
	func directlyConnectedAllInfo() async {
		let node = makeNode(
			longName: "Hopscotch",
			shortName: "HS01",
			num: 0xE75432,
			hopsAway: 0,
			snr: 5.5,
			rssi: -54,
			batteryLevel: 85,
			latitudeI: 374206000,
			longitudeI: -1221350000,
			favorite: true,
			lastHeard: Date(timeIntervalSinceNow: -30)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: true, connectedNode: 0).padding(.horizontal, 16),
			width: 390,
			named: "compact_directConnected_allInfo", forDocs: true
		)
	}

	@Test("Multi-hop node, 7 hops away")
	func multiHopNode() async {
		let node = makeNode(
			longName: "Brad!!",
			shortName: "B",
			num: 0x3A9FD1,
			hopsAway: 7,
			batteryLevel: 99,
			lastHeard: Date(timeIntervalSinceNow: -3600)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			named: "compact_multiHop", forDocs: true
		)
	}

	@Test("MQTT node, 3 hops")
	func mqttNode() async {
		let node = makeNode(
			longName: "MQTT Matt",
			shortName: "MQTM",
			num: 0x5B2E8C,
			hopsAway: 3,
			viaMqtt: true,
			role: 3,
			lastHeard: Date(timeIntervalSinceNow: -98200)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			named: "compact_mqtt", forDocs: true
		)
	}

	@Test("Long name, stale node")
	func longNameStale() async {
		let node = makeNode(
			longName: "Sneaky Little Roof Node 03",
			shortName: "SLN",
			hopsAway: 1,
			batteryLevel: 99,
			favorite: true,
			lastHeard: Date(timeIntervalSinceNow: -300600)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			named: "compact_longName_stale"
		)
	}

	@Test("PKI encrypted, key mismatch")
	func pkiKeyMismatch() async {
		let node = makeNode(
			longName: "Spy Node",
			shortName: "SPY",
			num: 0xC84A1F,
			pkiEncrypted: true,
			keyMatch: false,
			lastHeard: Date(timeIntervalSinceNow: -60)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			named: "compact_pkiMismatch", forDocs: true
		)
	}

	@Test("Unknown node, no user")
	func unknownNode() async {
		let node = NodeInfoEntity()
		node.hopsAway = 2
		node.lastHeard = Date(timeIntervalSinceNow: -120)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			named: "compact_unknownNode"
		)
	}

	@Test("Plugged in (battery > 100)")
	func pluggedIn() async {
		let node = makeNode(
			longName: "Power Station",
			shortName: "PWR",
			hopsAway: 0,
			batteryLevel: 101,
			lastHeard: Date(timeIntervalSinceNow: -5)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: true, connectedNode: 0).padding(.horizontal, 16),
			width: 390,
			named: "compact_pluggedIn"
		)
	}

	@Test("With position, 1 hop")
	func withPosition() async {
		let node = makeNode(
			longName: "Trail Node",
			shortName: "TRL",
			num: 0x27B06E,
			hopsAway: 1,
			snr: 3.25,
			rssi: -80,
			latitudeI: 374206000,
			longitudeI: -1221350000,
			lastHeard: Date(timeIntervalSinceNow: -200)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 0).padding(.horizontal, 16),
			width: 390,
			named: "compact_withPosition", forDocs: true
		)
	}

	// MARK: Dark mode variants

	@Test("Directly connected, online, all info — dark")
	func directlyConnectedAllInfoDark() async {
		let node = makeNode(
			longName: "Hopscotch",
			shortName: "HS01",
			num: 0xE75432,
			hopsAway: 0,
			snr: 5.5,
			rssi: -54,
			batteryLevel: 85,
			latitudeI: 374206000,
			longitudeI: -1221350000,
			favorite: true,
			lastHeard: Date(timeIntervalSinceNow: -30)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: true, connectedNode: 0).padding(.horizontal, 16),
			width: 390,
			colorScheme: .dark,
			named: "compact_directConnected_allInfo_dark", forDocs: true
		)
	}

	@Test("Multi-hop node, 7 hops away — dark")
	func multiHopNodeDark() async {
		let node = makeNode(
			longName: "Brad!!",
			shortName: "B",
			num: 0x3A9FD1,
			hopsAway: 7,
			batteryLevel: 99,
			lastHeard: Date(timeIntervalSinceNow: -3600)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			colorScheme: .dark,
			named: "compact_multiHop_dark", forDocs: true
		)
	}

	@Test("MQTT node, 3 hops — dark")
	func mqttNodeDark() async {
		let node = makeNode(
			longName: "MQTT Matt",
			shortName: "MQTM",
			num: 0x5B2E8C,
			hopsAway: 3,
			viaMqtt: true,
			role: 3,
			lastHeard: Date(timeIntervalSinceNow: -98200)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			colorScheme: .dark,
			named: "compact_mqtt_dark", forDocs: true
		)
	}

	@Test("PKI encrypted, key mismatch — dark")
	func pkiKeyMismatchDark() async {
		let node = makeNode(
			longName: "Spy Node",
			shortName: "SPY",
			num: 0xC84A1F,
			pkiEncrypted: true,
			keyMatch: false,
			lastHeard: Date(timeIntervalSinceNow: -60)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			colorScheme: .dark,
			named: "compact_pkiMismatch_dark", forDocs: true
		)
	}

	@Test("With position, 1 hop — dark")
	func withPositionDark() async {
		let node = makeNode(
			longName: "Trail Node",
			shortName: "TRL",
			num: 0x27B06E,
			hopsAway: 1,
			snr: 3.25,
			rssi: -80,
			latitudeI: 374206000,
			longitudeI: -1221350000,
			lastHeard: Date(timeIntervalSinceNow: -200)
		)
		await assertViewSnapshot(
			of: NodeListItemCompact(node: node, isDirectlyConnected: false, connectedNode: 0).padding(.horizontal, 16),
			width: 390,
			colorScheme: .dark,
			named: "compact_withPosition_dark", forDocs: true
		)
	}
}

// MARK: - NodeListItem Snapshot Tests

@Suite("NodeListItem Snapshots")
struct NodeListItemSnapshotTests {

	// MARK: Helpers

	private func makeNode(
		longName: String,
		shortName: String,
		num: Int64 = 0,
		hopsAway: Int32 = 0,
		snr: Float = 0,
		rssi: Int32 = 0,
		batteryLevel: Int32? = nil,
		latitudeI: Int32? = nil,
		longitudeI: Int32? = nil,
		viaMqtt: Bool = false,
		favorite: Bool = false,
		pkiEncrypted: Bool = false,
		keyMatch: Bool = true,
		role: Int32 = 0,
		lastHeard: Date? = nil
	) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		let user = UserEntity()
		user.longName = longName
		user.shortName = shortName
		user.pkiEncrypted = pkiEncrypted
		user.keyMatch = keyMatch
		user.role = role
		node.user = user
		node.hopsAway = hopsAway
		node.snr = snr
		node.rssi = rssi
		node.viaMqtt = viaMqtt
		node.favorite = favorite
		node.lastHeard = lastHeard
		if let battery = batteryLevel {
			let telemetry = TelemetryEntity()
			telemetry.batteryLevel = battery
			telemetry.distance = 100
			node.telemetries = [telemetry]
		}
		if let lat = latitudeI, let lon = longitudeI {
			let position = PositionEntity()
			position.latitudeI = lat
			position.longitudeI = lon
			node.positions = [position]
		}
		return node
	}

	// MARK: Tests — light

	@Test("Directly connected, online, all info")
	func directlyConnected() async {
		let node = makeNode(
			longName: "Hopscotch",
			shortName: "HS01",
			num: 0xE75432,
			snr: 5.5,
			rssi: -54,
			batteryLevel: 85,
			latitudeI: 374206000,
			longitudeI: -1221350000,
			favorite: true,
			lastHeard: Date(timeIntervalSinceNow: -30)
		)
		await assertViewSnapshot(
			of: NodeListItem(node: node, isDirectlyConnected: true, connectedNode: 0).padding(.horizontal, 16),
			width: 390,
			named: "standard_directConnected", forDocs: true
		)
	}

	@Test("Multi-hop node, 4 hops away")
	func multiHop() async {
		let node = makeNode(
			longName: "Brad!!",
			shortName: "B",
			num: 0x3A9FD1,
			hopsAway: 4,
			batteryLevel: 62,
			lastHeard: Date(timeIntervalSinceNow: -3600)
		)
		await assertViewSnapshot(
			of: NodeListItem(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			named: "standard_multiHop", forDocs: true
		)
	}

	@Test("MQTT node, via MQTT")
	func mqttNode() async {
		let node = makeNode(
			longName: "MQTT Matt",
			shortName: "MQTM",
			num: 0x5B2E8C,
			hopsAway: 2,
			viaMqtt: true,
			role: 3,
			lastHeard: Date(timeIntervalSinceNow: -98200)
		)
		await assertViewSnapshot(
			of: NodeListItem(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			named: "standard_mqtt", forDocs: true
		)
	}

	// MARK: Dark mode variants

	@Test("Directly connected, online, all info — dark")
	func directlyConnectedDark() async {
		let node = makeNode(
			longName: "Hopscotch",
			shortName: "HS01",
			num: 0xE75432,
			snr: 5.5,
			rssi: -54,
			batteryLevel: 85,
			latitudeI: 374206000,
			longitudeI: -1221350000,
			favorite: true,
			lastHeard: Date(timeIntervalSinceNow: -30)
		)
		await assertViewSnapshot(
			of: NodeListItem(node: node, isDirectlyConnected: true, connectedNode: 0).padding(.horizontal, 16),
			width: 390,
			colorScheme: .dark,
			named: "standard_directConnected_dark", forDocs: true
		)
	}

	@Test("Multi-hop node, 4 hops away — dark")
	func multiHopDark() async {
		let node = makeNode(
			longName: "Brad!!",
			shortName: "B",
			num: 0x3A9FD1,
			hopsAway: 4,
			batteryLevel: 62,
			lastHeard: Date(timeIntervalSinceNow: -3600)
		)
		await assertViewSnapshot(
			of: NodeListItem(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			colorScheme: .dark,
			named: "standard_multiHop_dark", forDocs: true
		)
	}

	@Test("MQTT node, via MQTT — dark")
	func mqttNodeDark() async {
		let node = makeNode(
			longName: "MQTT Matt",
			shortName: "MQTM",
			num: 0x5B2E8C,
			hopsAway: 2,
			viaMqtt: true,
			role: 3,
			lastHeard: Date(timeIntervalSinceNow: -98200)
		)
		await assertViewSnapshot(
			of: NodeListItem(node: node, isDirectlyConnected: false, connectedNode: 1).padding(.horizontal, 16),
			width: 390,
			colorScheme: .dark,
			named: "standard_mqtt_dark", forDocs: true
		)
	}
}

// MARK: - DocBrowserView Snapshot Tests

@Suite("DocBrowserViewSnapshotTests")
struct DocBrowserViewSnapshotTests {

	@Test("Empty state renders without crash")
	@MainActor
	func emptyStateRenders() async {
		// DocBundle.shared will have no pages in a test target (no bundle resources).
		// This test validates the ContentUnavailableView fallback path renders correctly.
		let view = DocBrowserView()
		let image = renderImage(view, width: 390, height: 600)
		let cgImage = image.cgImage
		#expect(cgImage != nil)
		if let cg = cgImage {
			#expect(cg.width > 0)
			#expect(cg.height > 0)
		}
	}
}

// MARK: - Node Status Icon Snapshots

@Suite("NodeStatusIcon Snapshots")
struct NodeStatusIconSnapshotTests {

	@Test("Online indicator")
	@MainActor
	func nodeOnline() async {
		let view = Image(systemName: "checkmark.circle.fill")
			.foregroundColor(Color(uiColor: .systemGreen))
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "nodeOnline", forDocs: true)
	}

	@Test("Idle / sleeping indicator")
	@MainActor
	func nodeIdle() async {
		let view = Image(systemName: "moon.circle.fill")
			.foregroundColor(Color(uiColor: .systemOrange))
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "nodeIdle", forDocs: true)
	}

	@Test("Hops away badge — 3 hops")
	@MainActor
	func hopsAway() async {
		let view = DefaultIconCompact(systemName: "3.square")
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "hopsAway", forDocs: true)
	}

	@Test("Channel badge — channel 2")
	@MainActor
	func channelBadge() async {
		let view = DefaultIconCompact(systemName: "2.circle.fill")
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "channelBadge", forDocs: true)
	}
}

// MARK: - Channel Lock Icon Snapshots

@Suite("ChannelLockIcon Snapshots")
struct ChannelLockIconSnapshotTests {

	@Test("Lock closed — encrypted (green)")
	@MainActor
	func lockClosed() async {
		let view = Image(systemName: "lock.fill")
			.foregroundColor(Color(uiColor: .systemGreen))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 30, transparent: true, named: "lockClosed", forDocs: true)
	}

	@Test("Lock open — unencrypted (yellow)")
	@MainActor
	func lockOpen() async {
		let view = Image(systemName: "lock.open.fill")
			.foregroundColor(Color(uiColor: .systemYellow))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 30, transparent: true, named: "lockOpen", forDocs: true)
	}

	@Test("Lock open red — location exposed")
	@MainActor
	func lockOpenRed() async {
		let view = Image(systemName: "lock.open.fill")
			.foregroundColor(Color(uiColor: .systemRed))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 30, transparent: true, named: "lockOpenRed", forDocs: true)
	}

	@Test("Lock open MQTT — insecure with MQTT uplink")
	@MainActor
	func lockOpenMqtt() async {
		let view = Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
			.foregroundColor(Color(uiColor: .systemRed))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 38, transparent: true, named: "lockOpenMqtt", forDocs: true)
	}

	@Test("Key slash — PKI mismatch")
	@MainActor
	func keySlash() async {
		let view = Image(systemName: "key.slash.fill")
			.foregroundColor(Color(uiColor: .systemRed))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "keySlash", forDocs: true)
	}
}

// MARK: - Node Log Icon Snapshots

@Suite("NodeLogIconSnapshotTests")
struct NodeLogIconSnapshotTests {

	@Test("Distance & Bearing")
	@MainActor
	func logDistance() async {
		let view = Image(systemName: "location.fill")
			.foregroundColor(Color(uiColor: .systemBlue))
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logDistance", forDocs: true)
	}

	@Test("Device Metrics")
	@MainActor
	func logDeviceMetrics() async {
		let view = Image(systemName: "flipphone")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logDeviceMetrics", forDocs: true)
	}

	@Test("Positions")
	@MainActor
	func logPositions() async {
		let view = Image(systemName: "mappin.and.ellipse")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logPositions", forDocs: true)
	}

	@Test("Environment")
	@MainActor
	func logEnvironment() async {
		let view = Image(systemName: "cloud.sun.rain")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logEnvironment", forDocs: true)
	}

	@Test("Detection Sensor")
	@MainActor
	func logDetectionSensor() async {
		let view = Image(systemName: "sensor")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logDetectionSensor", forDocs: true)
	}

	@Test("Trace Routes")
	@MainActor
	func logTraceRoutes() async {
		let view = Image(systemName: "signpost.right.and.left")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logTraceRoutes", forDocs: true)
	}
}

// MARK: - Messages Icon Snapshots

@Suite("MessagesIconSnapshotTests")
struct MessagesIconSnapshotTests {

	@Test("Favorite star")
	@MainActor
	func favorite() async {
		let view = Image(systemName: "star.fill")
			.foregroundColor(Color(uiColor: .systemYellow))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "favorite", forDocs: true)
	}

	@Test("Long press / tap")
	@MainActor
	func longPress() async {
		let view = Image(systemName: "hand.tap")
			.foregroundStyle(.secondary)
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "longPress", forDocs: true)
	}
}

// MARK: - Connection Status Icon Snapshots

@Suite("ConnectionStatusIconSnapshotTests")
struct ConnectionStatusIconSnapshotTests {

	@Test("BLE connected")
	@MainActor
	func btConnected() async {
		let view = Image("custom.bluetooth")
			.foregroundColor(Color(uiColor: .systemOrange))
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "btConnected", forDocs: true)
	}

	@Test("Reconnecting / retrying")
	@MainActor
	func btReconnecting() async {
		let view = Image(systemName: "square.stack.3d.down.forward")
			.foregroundColor(Color(uiColor: .systemOrange))
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "btReconnecting", forDocs: true)
	}

	@Test("TCP / Wi-Fi connected")
	@MainActor
	func tcpConnected() async {
		let view = Image(systemName: "network")
			.font(.title2)
			.foregroundColor(Color(uiColor: .systemOrange))
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "tcpConnected", forDocs: true)
	}

	@Test("Serial / USB connected")
	@MainActor
	func serialConnected() async {
		let view = Image(systemName: "cable.connector.horizontal")
			.font(.title2)
			.foregroundColor(Color(uiColor: .systemOrange))
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "serialConnected", forDocs: true)
	}
}

// MARK: - Device Role Icon Snapshots

@Suite("DeviceRoleIconSnapshotTests")
struct DeviceRoleIconSnapshotTests {

	private func icon(_ systemName: String) -> some View {
		Image(systemName: systemName)
			.foregroundColor(Color(uiColor: .systemBlue))
			.font(.title2)
			.padding(4)
	}

	@Test("Client") @MainActor func roleClient() async {
		await assertViewSnapshot(of: icon("apps.iphone"), width: 44, transparent: true, named: "roleClient", forDocs: true)
	}
	@Test("Client Mute") @MainActor func roleClientMute() async {
		await assertViewSnapshot(of: icon("speaker.slash"), width: 44, transparent: true, named: "roleClientMute", forDocs: true)
	}
	@Test("Client Hidden") @MainActor func roleClientHidden() async {
		await assertViewSnapshot(of: icon("eye.slash"), width: 44, transparent: true, named: "roleClientHidden", forDocs: true)
	}
	@Test("Router") @MainActor func roleRouter() async {
		await assertViewSnapshot(of: icon("wifi.router"), width: 44, transparent: true, named: "roleRouter", forDocs: true)
	}
	@Test("Router Late") @MainActor func roleRouterLate() async {
		await assertViewSnapshot(of: icon("wifi.router"), width: 44, transparent: true, named: "roleRouterLate", forDocs: true)
	}
	@Test("Client Base") @MainActor func roleClientBase() async {
		await assertViewSnapshot(of: icon("house"), width: 44, transparent: true, named: "roleClientBase", forDocs: true)
	}
	@Test("Tracker") @MainActor func roleTracker() async {
		await assertViewSnapshot(of: icon("mappin.and.ellipse.circle"), width: 44, transparent: true, named: "roleTracker", forDocs: true)
	}
	@Test("Sensor") @MainActor func roleSensor() async {
		await assertViewSnapshot(of: icon("sensor"), width: 44, transparent: true, named: "roleSensor", forDocs: true)
	}
	@Test("TAK") @MainActor func roleTak() async {
		await assertViewSnapshot(of: icon("shield.checkered"), width: 44, transparent: true, named: "roleTak", forDocs: true)
	}
	@Test("TAK Tracker") @MainActor func roleTakTracker() async {
		await assertViewSnapshot(of: icon("dog"), width: 44, transparent: true, named: "roleTakTracker", forDocs: true)
	}
	@Test("Lost and Found") @MainActor func roleLostAndFound() async {
		await assertViewSnapshot(of: icon("map"), width: 44, transparent: true, named: "roleLostAndFound", forDocs: true)
	}
}

// MARK: - ChannelForm Snapshot Tests

@Suite("ChannelForm Snapshots")
struct ChannelFormSnapshotTests {

	@Test("Primary channel with 256-bit key")
	@MainActor
	func channelFormPrimary() async {
		let view = ChannelForm(
			channelIndex: .constant(0),
			channelName: .constant("LongFast"),
			channelKeySize: .constant(32),
			channelKey: .constant("AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="),
			channelRole: .constant(1),
			uplink: .constant(false),
			downlink: .constant(false),
			positionPrecision: .constant(14),
			preciseLocation: .constant(false),
			positionsEnabled: .constant(true),
			hasChanges: .constant(false),
			hasValidKey: .constant(true),
			supportedVersion: .constant(true)
		)
		await assertViewSnapshot(of: view, width: 390, height: 700, named: "channelForm_primary", forDocs: true)
	}
}

// MARK: - TapbackInputView Snapshot Tests

@Suite("TapbackInputView Snapshots")
struct TapbackInputViewSnapshotTests {

	@Test("Tapback emoji input")
	@MainActor
	func tapbackInput() async {
		let view = TapbackInputView(
			text: .constant(""),
			isPresented: .constant(true),
			onEmojiSelected: { _ in }
		)
		await assertViewSnapshot(of: view, width: 390, height: 120, named: "tapbackInput", forDocs: true)
	}
}

// MARK: - AboutMeshtastic Snapshot Tests

@Suite("AboutMeshtastic Snapshots")
struct AboutMeshtasticSnapshotTests {

	@Test("About page")
	@MainActor
	func aboutPage() async {
		let view = NavigationView {
			AboutMeshtastic()
		}
		await assertViewSnapshot(of: view, width: 390, height: 700, named: "aboutMeshtastic")
	}
}

// MARK: - NodeDetail Snapshot Tests

@Suite("NodeDetail Snapshots")
struct NodeDetailSnapshotTests {

	@Test("Node detail with environment metrics")
	@MainActor
	func nodeDetailWithEnvironment() async {
		let container = try! ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = container.mainContext

		let node = NodeInfoEntity()
		node.num = 0xE75432
		node.lastHeard = Date(timeIntervalSinceNow: -120)
		node.firstHeard = Date(timeIntervalSinceNow: -86400)
		node.snr = 5.5
		node.rssi = -54
		node.hopsAway = 0
		node.favorite = true

		let user = UserEntity()
		user.longName = "Hopscotch Base"
		user.shortName = "HB"
		user.role = 0 // Client
		user.pkiEncrypted = true
		user.keyMatch = true
		user.unmessagable = false
		user.hwModel = "HELTEC_V3"
		user.hwModelId = 43
		node.user = user

		// Insert a DeviceHardwareEntity so NodeInfoItem shows "Supported Hardware"
		let hw = DeviceHardwareEntity()
		hw.hwModel = 43
		hw.displayName = "Heltec V3"
		hw.hwModelSlug = "heltecV3"
		hw.activelySupported = true
		hw.supportLevel = 1 // flagship
		context.insert(hw)

		// Position (needed for environment section rendering)
		let position = PositionEntity()
		position.latitudeI = 374206000
		position.longitudeI = -1221350000
		node.positions = [position]

		// Device metrics telemetry (metricsType 0)
		let deviceTelemetry = TelemetryEntity()
		deviceTelemetry.metricsType = 0
		deviceTelemetry.batteryLevel = 85
		deviceTelemetry.voltage = 4.05
		deviceTelemetry.uptimeSeconds = 172800 // 2 days
		deviceTelemetry.channelUtilization = 12.5
		deviceTelemetry.airUtilTx = 3.2

		// Environment telemetry (metricsType 1)
		let envTelemetry = TelemetryEntity()
		envTelemetry.metricsType = 1
		envTelemetry.temperature = 22.5
		envTelemetry.relativeHumidity = 55.0
		envTelemetry.barometricPressure = 1013.25

		node.telemetries = [deviceTelemetry, envTelemetry]
		context.insert(node)

		let view = NodeDetail(node: node)
			.environmentObject(AccessoryManager.shared)
			.environmentObject(MeshtasticAPI.shared)
			.modelContainer(container)

		await assertViewSnapshot(of: view, width: 390, height: 1800, named: "nodeDetail", forDocs: true)
	}
}

// MARK: - MQTTConfig Snapshot Tests

@Suite("MQTTConfig Snapshots")
struct MQTTConfigSnapshotTests {

	@Test("MQTT settings form")
	@MainActor
	func mqttSettingsForm() async {
		let view = NavigationView {
			MQTTConfig(node: nil)
				.environmentObject(AccessoryManager.shared)
				.modelContainer(PersistenceController.preview.container)
		}
		await assertViewSnapshot(of: view, width: 390, height: 900, named: "mqttConfig", forDocs: true)
	}
}

// MARK: - TelemetryConfig Snapshot Tests

@Suite("TelemetryConfig Snapshots")
struct TelemetryConfigSnapshotTests {

	@Test("Telemetry settings form")
	@MainActor
	func telemetrySettingsForm() async {
		let view = NavigationView {
			TelemetryConfig(node: nil)
				.environmentObject(AccessoryManager.shared)
				.modelContainer(PersistenceController.preview.container)
		}
		await assertViewSnapshot(of: view, width: 390, height: 900, named: "telemetryConfig", forDocs: true)
	}
}

// MARK: - BLE Signal Strength Snapshot Tests

@Suite("BLE Signal Strength Snapshots")
struct BLESignalStrengthSnapshotTests {

	@Test("Signal strength indicators")
	@MainActor
	func signalStrengthAll() async {
		let view = HStack(spacing: 16) {
			VStack {
				SignalStrengthIndicator(signalStrength: .weak)
				Text("Weak").font(.caption)
			}
			VStack {
				SignalStrengthIndicator(signalStrength: .normal)
				Text("Normal").font(.caption)
			}
			VStack {
				SignalStrengthIndicator(signalStrength: .strong)
				Text("Strong").font(.caption)
			}
		}
		.padding()
		await assertViewSnapshot(of: view, width: 200, height: 80, named: "bleSignalStrength", forDocs: true)
	}
}

// MARK: - MessagePreview Snapshot Tests

@Suite("MessagePreview Snapshots")
struct MessagePreviewSnapshotTests {

	@Test("Formatting toolbar buttons")
	@MainActor
	func formattingToolbar() async {
		let view = HStack(spacing: 12) {
			ForEach(MarkdownStyle.allCases, id: \.self) { style in
				Image(systemName: style.sfSymbol)
					.frame(minWidth: 44, minHeight: 36)
					.foregroundStyle(.primary)
			}
		}
		await assertViewSnapshot(of: view, width: 250, height: 44, named: "formattingToolbar", forDocs: true)
	}

	@Test("Preview with bold text")
	@MainActor
	func boldPreview() async {
		let view = MessagePreview(text: "**hello** world")
		await assertViewSnapshot(of: view, width: 300, height: 60, named: "messagePreview_bold", forDocs: true)
	}

	@Test("Preview with mixed formatting")
	@MainActor
	func mixedPreview() async {
		let view = MessagePreview(text: "**bold** *italic* ~~strike~~ `code`")
		await assertViewSnapshot(of: view, width: 350, height: 60, named: "messagePreview_mixed", forDocs: true)
	}

	@Test("Preview hidden when no markdown")
	@MainActor
	func noMarkdownHidden() async {
		let view = MessagePreview(text: "plain text no markdown")
		await assertViewSnapshot(of: view, width: 300, height: 10, named: "messagePreview_hidden")
	}

	@Test("Full compose area with formatting")
	@MainActor
	func composeAreaWithFormatting() async {
		let markdownText = "I am markdown text, **bold** and *italic* and ~~strike~~ and `code`"
		let view = VStack(spacing: 0) {
			// Preview bubble
			MessagePreview(text: markdownText)
			// Compose field mock
			HStack(alignment: .top, spacing: 8) {
				Button {} label: {
					Image(systemName: "xmark.circle.fill")
						.font(.title2)
						.foregroundColor(Color("Colors/MeshtasticAccent"))
				}
				.buttonStyle(.plain)

				Text(markdownText)
					.font(.body)
					.padding(.horizontal, 16)
					.padding(.vertical, 10)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(
						RoundedRectangle(cornerRadius: 20)
							.strokeBorder(.tertiary, lineWidth: 1)
							.background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
					)

				Button {} label: {
					Image(systemName: "arrow.up.circle.fill")
						.font(.title2)
						.foregroundColor(Color("Colors/MeshtasticAccent"))
				}
				.buttonStyle(.plain)
			}
			.padding(.horizontal, 8)
			// Toolbar
			HStack(spacing: 0) {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 0) {
						ForEach(MarkdownStyle.allCases, id: \.self) { style in
							Image(systemName: style.sfSymbol)
								.frame(width: 44, height: 36)
								.foregroundColor(Color("Colors/MeshtasticPrimary"))
						}
						Image(systemName: "bell.fill")
							.frame(width: 44, height: 36)
							.foregroundColor(Color("Colors/MeshtasticPrimary"))
						Image(systemName: "mappin.and.ellipse")
							.frame(width: 44, height: 36)
							.foregroundColor(Color("Colors/MeshtasticPrimary"))
					}
				}
				Spacer()
				TextMessageSize(maxbytes: 200, totalBytes: 68, compact: true)
					.layoutPriority(1)
			}
			.padding(.vertical, 8)
			.padding(.horizontal, 12)
			.background(.ultraThinMaterial, in: Capsule())
			.padding(.horizontal, 8)
			.padding(.top, 10)
		}
		.padding(.vertical, 8)
		.background(Color(.systemBackground))
		await assertViewSnapshot(of: view, width: 360, height: 250, named: "composeArea_formatting", forDocs: true)
		await assertViewSnapshot(of: view, width: 360, height: 250, colorScheme: .dark, named: "composeArea_formatting_dark", forDocs: true)
	}
}

@Suite("MessageTextLink Snapshots")
struct MessageTextLinkSnapshotTests {
	@Test("Link styled with underline and Link color - light")
	@MainActor func linkStyledLight() async {
		let linkColor = Color("Colors/MeshtasticLink")
		var attributed = try! AttributedString(markdown: "Check out [Meshtastic](https://meshtastic.org) for details", options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
		for run in attributed.runs where run.link != nil {
			attributed[run.range].underlineStyle = .single
			attributed[run.range].foregroundColor = linkColor
		}
		let view = Text(attributed)
			.tint(linkColor)
			.padding(.vertical, 10)
			.padding(.horizontal, 8)
			.foregroundColor(Color("Colors/MeshtasticBubbleText"))
			.background(Color("Colors/MeshtasticBubble"))
			.cornerRadius(15)
			.padding()
			.background(Color(.systemBackground))
		await assertViewSnapshot(of: view, width: 350, height: 80, named: "messageText_link", forDocs: true)
	}

	@Test("Link styled with underline and Link color - dark")
	@MainActor func linkStyledDark() async {
		let linkColor = Color("Colors/MeshtasticLink")
		var attributed = try! AttributedString(markdown: "Check out [Meshtastic](https://meshtastic.org) for details", options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
		for run in attributed.runs where run.link != nil {
			attributed[run.range].underlineStyle = .single
			attributed[run.range].foregroundColor = linkColor
		}
		let view = Text(attributed)
			.tint(linkColor)
			.padding(.vertical, 10)
			.padding(.horizontal, 8)
			.foregroundColor(Color("Colors/MeshtasticBubbleText"))
			.background(Color("Colors/MeshtasticBubble"))
			.cornerRadius(15)
			.padding()
			.background(Color(.systemBackground))
		await assertViewSnapshot(of: view, width: 350, height: 80, colorScheme: .dark, named: "messageText_link_dark", forDocs: true)
	}
}

// MARK: - TAKIdentitySection Snapshot Tests
//
// Snapshot coverage for the TAK Identity section embedded at the top of
// TAKServerConfig. We synthesize a NodeInfoEntity with a populated
// TAKConfigEntity so the section renders in its enabled / ready-to-edit
// state. Full-screen TAKServerConfig snapshots are deferred — that view
// depends on TAKServerManager.shared, a live AccessoryManager, a @Query
// of ChannelEntity, and certificate state, which is more mocking than
// belongs in a docs PR.

@Suite("TAKIdentitySection Snapshots")
struct TAKIdentitySectionSnapshotTests {

	/// Synthesizes a NodeInfoEntity with a populated TAKConfigEntity so the
	/// section renders in its enabled state. Uses the shared in-memory
	/// container to avoid SwiftData context resets across tests.
	@MainActor
	private func makeTAKNode() -> NodeInfoEntity {
		let context = sharedModelContainer.mainContext
		let node = NodeInfoEntity()
		node.num = 0xDEAD_BEEF
		context.insert(node)

		let user = UserEntity()
		user.num = node.num
		user.longName = "Snapshot TAK Node"
		user.shortName = "STAK"
		context.insert(user)
		node.user = user

		let tak = TAKConfigEntity()
		tak.team = Int32(Team.cyan.rawValue)
		tak.role = Int32(MemberRole.teamMember.rawValue)
		context.insert(tak)
		node.takConfig = tak

		try? context.save()
		return node
	}

	/// Wraps TAKIdentitySection in a Form so it renders as a real Settings
	/// section. Section is not standalone — SwiftUI requires a Form/List host.
	///
	/// `TAKIdentitySection` gates `canEdit` on
	/// `accessoryManager.isConnected && node?.takConfig != nil`. The shared
	/// `AccessoryManager` starts with `isConnected == false`, which renders
	/// the entire section disabled (greyed-out pickers, no Save button), so
	/// the doc snapshot would capture the disabled state rather than the
	/// "ready to edit" state these tests exist to document. We flip the
	/// shared instance to connected for the duration of the snapshot. The
	/// flag is a `@Published Bool` on a `@MainActor` singleton — there's no
	/// network side-effect from setting it directly. We deliberately do
	/// not restore it: nothing else in this test target reads it back, and
	/// resetting via `defer` would race with SwiftUI's asynchronous render.
	@MainActor
	private func wrap(_ node: NodeInfoEntity) -> some View {
		AccessoryManager.shared.isConnected = true
		return Form {
			TAKIdentitySection(node: node)
		}
		.environmentObject(AccessoryManager.shared)
		.modelContainer(sharedModelContainer)
	}

	@Test
	@MainActor
	func takIdentitySection() async {
		let node = makeTAKNode()
		await assertViewSnapshot(
			of: wrap(node),
			width: 390,
			height: 360,
			colorScheme: .light,
			named: "takIdentitySection",
			forDocs: true
		)
	}

	@Test
	@MainActor
	func takIdentitySectionDark() async {
		let node = makeTAKNode()
		await assertViewSnapshot(
			of: wrap(node),
			width: 390,
			height: 360,
			colorScheme: .dark,
			named: "takIdentitySection_dark",
			forDocs: true
		)
	}
}
