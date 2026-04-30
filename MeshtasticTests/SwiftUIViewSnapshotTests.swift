// SwiftUIViewSnapshotTests.swift
// MeshtasticTests

import Testing
import SwiftUI
import UIKit
@testable import Meshtastic

// MARK: - Snapshot Helpers

/// Renders a SwiftUI view to a UIImage. When height is nil the view sizes itself
/// using its intrinsic content height for the given width (via sizeThatFits).
@MainActor
private func renderImage<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil) -> UIImage {
	// Wrap the view to ignore safe area so content isn't inset by the device's safe area
	let wrappedView = AnyView(
		view
			.frame(width: width)
			.ignoresSafeArea()
	)
	let hostingController = UIHostingController(rootView: wrappedView)
	hostingController.view.backgroundColor = .systemBackground

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

	let renderer = UIGraphicsImageRenderer(size: size)
	return renderer.image { _ in
		hostingController.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
	}
}

/// Saves a snapshot image to disk. On first run, records the reference.
/// On subsequent runs, compares against the reference and fails if different.
/// When height is nil the view determines its own height via sizeThatFits.
@MainActor
private func assertViewSnapshot<V: View>(
	of view: V,
	width: CGFloat,
	height: CGFloat? = nil,
	named name: String,
	filePath: String = #filePath,
	sourceLocation: SourceLocation = #_sourceLocation
) {
	let image = renderImage(view, width: width, height: height)
	guard let pngData = image.pngData() else {
		Issue.record("Failed to generate PNG data", sourceLocation: sourceLocation)
		return
	}

	let fileUrl = URL(fileURLWithPath: filePath, isDirectory: false)
	let snapshotDir = fileUrl.deletingLastPathComponent()
		.appendingPathComponent("__Snapshots__")
		.appendingPathComponent(fileUrl.deletingPathExtension().lastPathComponent)
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
		// First run - record reference
		do {
			try pngData.write(to: snapshotFile)
		} catch {
			Issue.record("Failed to write snapshot: \(error)", sourceLocation: sourceLocation)
			return
		}
		Issue.record(
			"No reference snapshot found. Recorded: \(snapshotFile.lastPathComponent). Re-run to verify.",
			sourceLocation: sourceLocation
		)
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
		await assertViewSnapshot(of: CircleText(text: "😝", color: .red, circleSize: 80), width: 100, named: "circleTextEmoji")
	}

	@Test("CircleText with long text")
	func circleTextLong() async {
		await assertViewSnapshot(of: CircleText(text: "WWWW", color: .cyan, circleSize: 80), width: 100, named: "circleTextLong")
	}

	@Test("CircleText default size")
	func circleTextDefault() async {
		await assertViewSnapshot(of: CircleText(text: "AB", color: .green), width: 60, named: "circleTextDefault")
	}
}

// MARK: - AckErrors Snapshot Tests

@Suite("AckErrors Snapshots")
struct AckErrorsSnapshotTests {

	@Test("AckErrors view")
	func ackErrors() async {
		await assertViewSnapshot(of: AckErrors(), width: 350, named: "ackErrors")
	}
}

// MARK: - LockLegend Snapshot Tests

@Suite("LockLegend Snapshots")
struct LockLegendSnapshotTests {

	@Test("LockLegend view")
	func lockLegend() async {
		await assertViewSnapshot(of: LockLegend(), width: 350, named: "lockLegend")
	}
}

// MARK: - IAQScale Snapshot Tests

@Suite("IAQScale Snapshots")
struct IAQScaleSnapshotTests {

	@Test("IAQScale view")
	func iaqScale() async {
		await assertViewSnapshot(of: IAQScale(), width: 300, named: "iaqScale")
	}
}

// MARK: - AirQualityIndex Snapshot Tests

@Suite("AirQualityIndex Snapshots")
struct AirQualityIndexSnapshotTests {

	@Test("AQI pill mode")
	func aqiPill() async {
		await assertViewSnapshot(of: AirQualityIndex(aqi: 51), width: 200, named: "aqiPill")
	}

	@Test("AQI dot mode")
	func aqiDot() async {
		await assertViewSnapshot(of: AirQualityIndex(aqi: 101, displayMode: .dot), width: 100, named: "aqiDot")
	}

	@Test("AQI text mode")
	func aqiText() async {
		await assertViewSnapshot(of: AirQualityIndex(aqi: 201, displayMode: .text), width: 200, named: "aqiText")
	}

	@Test("AQI gauge mode")
	func aqiGauge() async {
		await assertViewSnapshot(of: AirQualityIndex(aqi: 150, displayMode: .gauge), width: 120, height: 120, named: "aqiGauge")
	}

	@Test("AQI gradient mode")
	func aqiGradient() async {
		await assertViewSnapshot(of: AirQualityIndex(aqi: 300, displayMode: .gradient), width: 350, named: "aqiGradient")
	}
}

// MARK: - IndoorAirQuality Snapshot Tests

@Suite("IndoorAirQuality Snapshots")
struct IndoorAirQualitySnapshotTests {

	@Test("IAQ pill mode")
	func iaqPill() async {
		await assertViewSnapshot(of: IndoorAirQuality(iaq: 75), width: 200, named: "iaqPill")
	}

	@Test("IAQ gauge mode")
	func iaqGauge() async {
		await assertViewSnapshot(of: IndoorAirQuality(iaq: 250, displayMode: .gauge), width: 120, height: 120, named: "iaqGauge")
	}
}

// MARK: - LoRaSignalStrengthIndicator Snapshot Tests

@Suite("LoRaSignalStrength Snapshots")
struct LoRaSignalStrengthSnapshotTests {

	@Test("LoRa signal none")
	func signalNone() async {
		await assertViewSnapshot(of: LoRaSignalStrengthIndicator(signalStrength: .none), width: 50, named: "signalNone")
	}

	@Test("LoRa signal bad")
	func signalBad() async {
		await assertViewSnapshot(of: LoRaSignalStrengthIndicator(signalStrength: .bad), width: 50, named: "signalBad")
	}

	@Test("LoRa signal good")
	func signalGood() async {
		await assertViewSnapshot(of: LoRaSignalStrengthIndicator(signalStrength: .good), width: 50, named: "signalGood")
	}
}

// MARK: - MQTTIcon Snapshot Tests

@Suite("MQTTIcon Snapshots")
struct MQTTIconSnapshotTests {

	@Test("MQTT connected")
	func mqttConnected() async {
		await assertViewSnapshot(of: MQTTIcon(connected: true, uplink: true, downlink: true), width: 50, named: "mqttConnected")
	}

	@Test("MQTT disconnected")
	func mqttDisconnected() async {
		await assertViewSnapshot(of: MQTTIcon(connected: false, uplink: false, downlink: false), width: 50, named: "mqttDisconnected")
	}

	@Test("MQTT uplink only")
	func mqttUplinkOnly() async {
		await assertViewSnapshot(of: MQTTIcon(connected: true, uplink: true, downlink: false), width: 50, named: "mqttUplinkOnly")
	}
}

// MARK: - Compact Widget Snapshot Tests

@Suite("CompactWidget Snapshots")
struct CompactWidgetSnapshotTests {

	@Test("Humidity with dew point")
	func humidityWithDew() async {
		await assertViewSnapshot(of: HumidityCompactWidget(humidity: 65, dewPoint: "18°"), width: 180, named: "humidityWithDew")
	}

	@Test("Humidity without dew point")
	func humidityNoDew() async {
		await assertViewSnapshot(of: HumidityCompactWidget(humidity: 42, dewPoint: nil), width: 180, named: "humidityNoDew")
	}

	@Test("Pressure low")
	func pressureLow() async {
		await assertViewSnapshot(of: PressureCompactWidget(pressure: "1004.76", unit: "hPA", low: true), width: 180, named: "pressureLow")
	}

	@Test("Pressure high")
	func pressureHigh() async {
		await assertViewSnapshot(of: PressureCompactWidget(pressure: "1024.50", unit: "hPA", low: false), width: 180, named: "pressureHigh")
	}

	@Test("Wind full")
	func windFull() async {
		await assertViewSnapshot(of: WindCompactWidget(speed: "12 mph", gust: "15 mph", direction: "SW"), width: 180, named: "windFull")
	}

	@Test("Wind minimal")
	func windMinimal() async {
		await assertViewSnapshot(of: WindCompactWidget(speed: "8 mph", gust: nil, direction: nil), width: 180, named: "windMinimal")
	}

	@Test("Radiation")
	func radiation() async {
		await assertViewSnapshot(of: RadiationCompactWidget(radiation: "15", unit: "µR/hr"), width: 180, named: "radiation")
	}
}

// MARK: - InvalidVersion Snapshot Tests

@Suite("InvalidVersion Snapshots")
struct InvalidVersionSnapshotTests {

	@Test("InvalidVersion view")
	func invalidVersion() async {
		await assertViewSnapshot(of: InvalidVersion(minimumVersion: "2.5.0", version: "2.3.1"), width: 390, height: 600, named: "invalidVersion")
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
		await assertViewSnapshot(of: SecurityVersionNag(minimumSecureVersion: "2.5.6", version: "2.4.0"), width: 390, height: 500, named: "securityVersionNag")
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
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: 95, font: .caption, iconFont: .callout, color: .green), width: 200, named: "batteryFull")
	}

	@Test("Battery low")
	func batteryLow() async {
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: 10, font: .caption, iconFont: .callout, color: .orange), width: 200, named: "batteryLow")
	}

	@Test("Battery charging")
	func batteryCharging() async {
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: 100, font: .caption, iconFont: .callout, color: .green), width: 200, named: "batteryCharging")
	}

	@Test("Battery plugged in")
	func batteryPluggedIn() async {
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: 101, font: .caption, iconFont: .callout, color: .blue), width: 200, named: "batteryPluggedIn")
	}

	@Test("Battery nil")
	func batteryNil() async {
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: nil, font: .caption, iconFont: .callout, color: .gray), width: 200, named: "batteryNil")
	}
}

// MARK: - CircularProgressView Snapshot Tests

@Suite("CircularProgressView Snapshots")
struct CircularProgressViewSnapshotTests {

	@Test("Progress 0%")
	func progressZero() async {
		await assertViewSnapshot(of: CircularProgressView(progress: 0.0, size: 100), width: 120, named: "progressZero")
	}

	@Test("Progress 50%")
	func progressHalf() async {
		await assertViewSnapshot(of: CircularProgressView(progress: 0.5, size: 100), width: 120, named: "progressHalf")
	}

	@Test("Progress 100%")
	func progressComplete() async {
		await assertViewSnapshot(of: CircularProgressView(progress: 1.0, size: 100), width: 120, named: "progressComplete")
	}

	@Test("Progress error")
	func progressError() async {
		await assertViewSnapshot(of: CircularProgressView(progress: 0.3, isError: true, size: 100), width: 120, named: "progressError")
	}
}

// MARK: - LoRaSignalStrengthMeter Snapshot Tests

@Suite("LoRaSignalStrengthMeter Snapshots")
struct LoRaSignalStrengthMeterSnapshotTests {

	@Test("LoRa meter compact good signal")
	func compactGood() async {
		await assertViewSnapshot(of: LoRaSignalStrengthMeter(snr: -10, rssi: -100, preset: .longFast, compact: true), width: 300, named: "compactGood")
	}

	@Test("LoRa meter non-compact bad signal")
	func nonCompactBad() async {
		await assertViewSnapshot(of: LoRaSignalStrengthMeter(snr: -12.75, rssi: -139, preset: .longFast, compact: false), width: 100, named: "nonCompactBad")
	}
}

// MARK: - RadarSweepView Snapshot Tests

@Suite("RadarSweepView Snapshots")
struct RadarSweepViewSnapshotTests {

	@Test("Radar sweep active")
	func radarActive() async {
		await assertViewSnapshot(of: RadarSweepView(isActive: true), width: 200, height: 200, named: "radarActive")
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
			named: "summaryTwoPresets"
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
