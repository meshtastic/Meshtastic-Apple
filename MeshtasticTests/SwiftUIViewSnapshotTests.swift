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
@MainActor
private func assertViewSnapshot<V: View>(
	of view: V,
	width: CGFloat,
	height: CGFloat? = nil,
	transparent: Bool = false,
	colorScheme: ColorScheme? = nil,
	named name: String,
	filePath: String = #filePath,
	sourceLocation: SourceLocation = #_sourceLocation
) {
	let image = renderImage(view, width: width, height: height, transparent: transparent, colorScheme: colorScheme)
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
		await assertViewSnapshot(of: CircleText(text: "AB", color: Color(uiColor: .systemGreen)), width: 60, transparent: true, named: "circleTextDefault")
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
			named: "aqi_all_modes_light"
		)
	}

	@Test("AQI — All Display Modes (Dark)")
	func aqiAllModesDark() async {
		await assertViewSnapshot(
			of: aqiGrid,
			width: 350,
			height: 820,
			colorScheme: .dark,
			named: "aqi_all_modes_dark"
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
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "mqttConnected")
	}

	@Test("MQTT disconnected")
	func mqttDisconnected() async {
		let view = Image(systemName: "arrow.up.arrow.down.circle.fill")
			.foregroundColor(Color(uiColor: .systemGray))
			.symbolRenderingMode(.hierarchical)
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "mqttDisconnected")
	}

	@Test("MQTT uplink only")
	func mqttUplinkOnly() async {
		let view = Image(systemName: "arrow.up.circle.fill")
			.foregroundColor(Color(uiColor: .systemGreen))
			.symbolRenderingMode(.hierarchical)
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "mqttUplinkOnly")
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
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: 95, font: .caption, iconFont: .callout, color: Color(uiColor: .systemGreen)), width: 200, named: "batteryFull")
	}

	@Test("Battery low")
	func batteryLow() async {
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: 10, font: .caption, iconFont: .callout, color: Color(uiColor: .systemOrange)), width: 200, named: "batteryLow")
	}

	@Test("Battery charging")
	func batteryCharging() async {
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: 100, font: .caption, iconFont: .callout, color: Color(uiColor: .systemGreen)), width: 200, named: "batteryCharging")
	}

	@Test("Battery plugged in")
	func batteryPluggedIn() async {
		await assertViewSnapshot(of: BatteryCompact(batteryLevel: 101, font: .caption, iconFont: .callout, color: Color(uiColor: .systemBlue)), width: 200, named: "batteryPluggedIn")
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
			named: "signalMeter_compact_all"
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
			named: "signalMeter_full_all"
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
			named: "signalBLE_all"
		)
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

// MARK: - Doc Map Preview

/// Purely-static SwiftUI "map" used for documentation screenshots.
/// Renders a stylised city-block background (no MapKit tile dependency) with
/// node circle annotations, connection lines, and an optional waypoint marker.
private struct DocMapPreviewView: View {
	struct NodePin: Identifiable {
		let id = UUID()
		let shortName: String
		let num: Int64
		let latitude: Double
		let longitude: Double
		let isDirect: Bool
		var isWaypoint: Bool = false
	}

	let userLatitude: Double
	let userLongitude: Double
	let pins: [NodePin]
	var colorScheme: ColorScheme = .light

	// Fixed canvas size for consistent rendering
	private let w: CGFloat = 390
	private let h: CGFloat = 300

	// Padded lat/lon extents so pins don't sit right at the edges
	private var minLat: Double {
		let lats = pins.map(\.latitude) + [userLatitude]
		let span = max((lats.max()! - lats.min()!) * 0.45, 0.003)
		return lats.min()! - span
	}
	private var maxLat: Double {
		let lats = pins.map(\.latitude) + [userLatitude]
		let span = max((lats.max()! - lats.min()!) * 0.45, 0.003)
		return lats.max()! + span
	}
	private var minLon: Double {
		let lons = pins.map(\.longitude) + [userLongitude]
		let span = max((lons.max()! - lons.min()!) * 0.45, 0.003)
		return lons.min()! - span
	}
	private var maxLon: Double {
		let lons = pins.map(\.longitude) + [userLongitude]
		let span = max((lons.max()! - lons.min()!) * 0.45, 0.003)
		return lons.max()! + span
	}

	/// Maps a lat/lon pair to a point in the fixed canvas coordinate space.
	private func toXY(_ lat: Double, _ lon: Double) -> CGPoint {
		let latRange = maxLat - minLat
		let lonRange = maxLon - minLon
		let x = lonRange > 0 ? CGFloat((lon - minLon) / lonRange) * w : w / 2
		let y = latRange > 0 ? CGFloat(1.0 - (lat - minLat) / latRange) * h : h / 2
		return CGPoint(x: x, y: y)
	}

	private var isDark: Bool { colorScheme == .dark }

	var body: some View {
		ZStack(alignment: .topLeading) {
			mapBackground
			linesOverlay
			// "You" marker
			let youPt = toXY(userLatitude, userLongitude)
			Image(systemName: "location.circle.fill")
				.foregroundStyle(.orange)
				.font(.system(size: 28))
				.shadow(color: .black.opacity(0.3), radius: 2)
				.position(youPt)
			// Node / waypoint pins
			ForEach(pins) { pin in
				if pin.isWaypoint {
					waypointMarker.position(toXY(pin.latitude, pin.longitude))
				} else {
					CircleText(
						text: pin.shortName,
						color: Color(UIColor(hex: UInt32(pin.num))),
						circleSize: 34
					)
					.shadow(color: .black.opacity(0.25), radius: 2)
					.position(toXY(pin.latitude, pin.longitude))
				}
			}
		}
		.frame(width: w, height: h)
		.clipped()
	}

	private var waypointMarker: some View {
		ZStack {
			Circle()
				.fill(Color.purple.opacity(0.85))
				.frame(width: 30, height: 30)
			Image(systemName: "star.fill")
				.font(.system(size: 14))
				.foregroundStyle(.white)
		}
		.shadow(color: .black.opacity(0.3), radius: 2)
	}

	private var mapBackground: some View {
		// Colour palette adapts for light/dark map styles
		let land  = isDark ? Color(red: 0.17, green: 0.20, blue: 0.15) : Color(red: 0.93, green: 0.94, blue: 0.89)
		let block = isDark ? Color(red: 0.23, green: 0.26, blue: 0.21) : Color(red: 0.97, green: 0.96, blue: 0.93)
		let road  = isDark ? Color(red: 0.32, green: 0.36, blue: 0.30).opacity(0.9) : Color.white.opacity(0.80)
		let park  = isDark ? Color(red: 0.10, green: 0.22, blue: 0.09).opacity(0.85) : Color(red: 0.70, green: 0.86, blue: 0.62).opacity(0.75)
		let water = isDark ? Color(red: 0.05, green: 0.13, blue: 0.24).opacity(0.90) : Color(red: 0.57, green: 0.79, blue: 0.93).opacity(0.72)

		return Canvas { ctx, size in
			// Land base
			ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(land))
			// City block grid
			var col: CGFloat = 0
			while col < size.width {
				var row: CGFloat = 0
				while row < size.height {
					ctx.fill(
						Path(CGRect(x: col + 5, y: row + 5, width: 45, height: 35)),
						with: .color(block)
					)
					row += 45
				}
				col += 55
			}
			// Horizontal roads
			var row: CGFloat = 0
			while row < size.height {
				ctx.fill(Path(CGRect(x: 0, y: row, width: size.width, height: 5)), with: .color(road))
				row += 45
			}
			// Vertical roads
			col = 0
			while col < size.width {
				ctx.fill(Path(CGRect(x: col, y: 0, width: 5, height: size.height)), with: .color(road))
				col += 55
			}
			// Park (bottom-right quadrant)
			ctx.fill(
				Path(CGRect(x: size.width * 0.60, y: size.height * 0.50, width: size.width * 0.40, height: size.height * 0.50)),
				with: .color(park)
			)
			// Water body (bottom-left corner)
			ctx.fill(
				Path(CGRect(x: 0, y: size.height * 0.72, width: size.width * 0.22, height: size.height * 0.28)),
				with: .color(water)
			)
		}
		.frame(width: w, height: h)
	}

	private var linesOverlay: some View {
		let userPt = toXY(userLatitude, userLongitude)
		let meshPins = pins.filter { !$0.isWaypoint }
		let nodePts = meshPins.map { toXY($0.latitude, $0.longitude) }
		let directFlags = meshPins.map { $0.isDirect }
		return Canvas { ctx, _ in
			for i in 0..<meshPins.count {
				var path = Path()
				path.move(to: userPt)
				path.addLine(to: nodePts[i])
				if directFlags[i] {
					ctx.stroke(path, with: .color(Color(red: 0.0, green: 0.72, blue: 0.2).opacity(0.70)),
								style: StrokeStyle(lineWidth: 2.5))
				} else {
					ctx.stroke(path, with: .color(Color(red: 1.0, green: 0.55, blue: 0.0).opacity(0.55)),
								style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
				}
			}
		}
		.frame(width: w, height: h)
	}
}

// MARK: - DocMapAnnotation Snapshot Tests

@Suite("DocMapAnnotation Snapshots")
struct DocMapAnnotationSnapshotTests {

	private func makeView(colorScheme: ColorScheme = .light) -> DocMapPreviewView {
		DocMapPreviewView(
			userLatitude: 37.7749,
			userLongitude: -122.4194,
			pins: [
				// Directly connected — HS01 "Hopscotch" (green solid line)
				.init(shortName: "HS01", num: 0xE75432, latitude: 37.7810, longitude: -122.4140, isDirect: true),
				// 1 hop — TRL "Trail Node" (orange dashed line)
				.init(shortName: "TRL", num: 0x27B06E, latitude: 37.7690, longitude: -122.4260, isDirect: false),
				// Multi-hop — B "Brad!!" (orange dashed)
				.init(shortName: "B", num: 0x3A9FD1, latitude: 37.7790, longitude: -122.4290, isDirect: false),
				// MQTT — MQTM "MQTT Matt" (orange dashed)
				.init(shortName: "MQTM", num: 0x5B2E8C, latitude: 37.7710, longitude: -122.4090, isDirect: false),
				// Waypoint — in the park area, away from other pins
				.init(shortName: "★", num: 0, latitude: 37.7680, longitude: -122.4065, isDirect: false, isWaypoint: true)
			],
			colorScheme: colorScheme
		)
	}

	@Test("Map with node annotations (light)")
	@MainActor
	func mapAnnotations() async {
		await assertViewSnapshot(
			of: makeView(),
			width: 390,
			height: 300,
			named: "mapAnnotations"
		)
	}

	@Test("Map with node annotations (dark)")
	@MainActor
	func mapAnnotationsDark() async {
		await assertViewSnapshot(
			of: makeView(colorScheme: .dark),
			width: 390,
			height: 300,
			colorScheme: .dark,
			named: "mapAnnotations_dark"
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
			named: "compact_directConnected_allInfo"
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
			named: "compact_multiHop"
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
			named: "compact_mqtt"
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
			named: "compact_pkiMismatch"
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
			named: "compact_withPosition"
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
			named: "compact_directConnected_allInfo_dark"
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
			named: "compact_multiHop_dark"
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
			named: "compact_mqtt_dark"
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
			named: "compact_pkiMismatch_dark"
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
			named: "compact_withPosition_dark"
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
			named: "standard_directConnected"
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
			named: "standard_multiHop"
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
			named: "standard_mqtt"
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
			named: "standard_directConnected_dark"
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
			named: "standard_multiHop_dark"
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
			named: "standard_mqtt_dark"
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
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "nodeOnline")
	}

	@Test("Idle / sleeping indicator")
	@MainActor
	func nodeIdle() async {
		let view = Image(systemName: "moon.circle.fill")
			.foregroundColor(Color(uiColor: .systemOrange))
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "nodeIdle")
	}

	@Test("Hops away badge — 3 hops")
	@MainActor
	func hopsAway() async {
		let view = DefaultIconCompact(systemName: "3.square")
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "hopsAway")
	}

	@Test("Channel badge — channel 2")
	@MainActor
	func channelBadge() async {
		let view = DefaultIconCompact(systemName: "2.circle.fill")
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "channelBadge")
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
		await assertViewSnapshot(of: view, width: 30, transparent: true, named: "lockClosed")
	}

	@Test("Lock open — unencrypted (yellow)")
	@MainActor
	func lockOpen() async {
		let view = Image(systemName: "lock.open.fill")
			.foregroundColor(Color(uiColor: .systemYellow))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 30, transparent: true, named: "lockOpen")
	}

	@Test("Lock open red — location exposed")
	@MainActor
	func lockOpenRed() async {
		let view = Image(systemName: "lock.open.fill")
			.foregroundColor(Color(uiColor: .systemRed))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 30, transparent: true, named: "lockOpenRed")
	}

	@Test("Lock open MQTT — insecure with MQTT uplink")
	@MainActor
	func lockOpenMqtt() async {
		let view = Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
			.foregroundColor(Color(uiColor: .systemRed))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 38, transparent: true, named: "lockOpenMqtt")
	}

	@Test("Key slash — PKI mismatch")
	@MainActor
	func keySlash() async {
		let view = Image(systemName: "key.slash.fill")
			.foregroundColor(Color(uiColor: .systemRed))
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "keySlash")
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
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logDistance")
	}

	@Test("Device Metrics")
	@MainActor
	func logDeviceMetrics() async {
		let view = Image(systemName: "flipphone")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logDeviceMetrics")
	}

	@Test("Positions")
	@MainActor
	func logPositions() async {
		let view = Image(systemName: "mappin.and.ellipse")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logPositions")
	}

	@Test("Environment")
	@MainActor
	func logEnvironment() async {
		let view = Image(systemName: "cloud.sun.rain")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logEnvironment")
	}

	@Test("Detection Sensor")
	@MainActor
	func logDetectionSensor() async {
		let view = Image(systemName: "sensor")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logDetectionSensor")
	}

	@Test("Trace Routes")
	@MainActor
	func logTraceRoutes() async {
		let view = Image(systemName: "signpost.right.and.left")
			.foregroundStyle(.secondary)
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "logTraceRoutes")
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
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "favorite")
	}

	@Test("Long press / tap")
	@MainActor
	func longPress() async {
		let view = Image(systemName: "hand.tap")
			.foregroundStyle(.secondary)
			.font(.title)
			.padding(2)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "longPress")
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
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "btConnected")
	}

	@Test("Reconnecting / retrying")
	@MainActor
	func btReconnecting() async {
		let view = Image(systemName: "square.stack.3d.down.forward")
			.foregroundColor(Color(uiColor: .systemOrange))
			.font(.title2)
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "btReconnecting")
	}

	@Test("TCP / Wi-Fi connected")
	@MainActor
	func tcpConnected() async {
		let view = Image(systemName: "network")
			.font(.title2)
			.foregroundColor(Color(uiColor: .systemOrange))
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "tcpConnected")
	}

	@Test("Serial / USB connected")
	@MainActor
	func serialConnected() async {
		let view = Image(systemName: "cable.connector.horizontal")
			.font(.title2)
			.foregroundColor(Color(uiColor: .systemOrange))
			.padding(4)
		await assertViewSnapshot(of: view, width: 44, transparent: true, named: "serialConnected")
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
		await assertViewSnapshot(of: icon("apps.iphone"), width: 44, transparent: true, named: "roleClient")
	}
	@Test("Client Mute") @MainActor func roleClientMute() async {
		await assertViewSnapshot(of: icon("speaker.slash"), width: 44, transparent: true, named: "roleClientMute")
	}
	@Test("Client Hidden") @MainActor func roleClientHidden() async {
		await assertViewSnapshot(of: icon("eye.slash"), width: 44, transparent: true, named: "roleClientHidden")
	}
	@Test("Router") @MainActor func roleRouter() async {
		await assertViewSnapshot(of: icon("wifi.router"), width: 44, transparent: true, named: "roleRouter")
	}
	@Test("Router Late") @MainActor func roleRouterLate() async {
		await assertViewSnapshot(of: icon("wifi.router"), width: 44, transparent: true, named: "roleRouterLate")
	}
	@Test("Client Base") @MainActor func roleClientBase() async {
		await assertViewSnapshot(of: icon("house"), width: 44, transparent: true, named: "roleClientBase")
	}
	@Test("Tracker") @MainActor func roleTracker() async {
		await assertViewSnapshot(of: icon("mappin.and.ellipse.circle"), width: 44, transparent: true, named: "roleTracker")
	}
	@Test("Sensor") @MainActor func roleSensor() async {
		await assertViewSnapshot(of: icon("sensor"), width: 44, transparent: true, named: "roleSensor")
	}
	@Test("TAK") @MainActor func roleTak() async {
		await assertViewSnapshot(of: icon("shield.checkered"), width: 44, transparent: true, named: "roleTak")
	}
	@Test("TAK Tracker") @MainActor func roleTakTracker() async {
		await assertViewSnapshot(of: icon("dog"), width: 44, transparent: true, named: "roleTakTracker")
	}
	@Test("Lost and Found") @MainActor func roleLostAndFound() async {
		await assertViewSnapshot(of: icon("map"), width: 44, transparent: true, named: "roleLostAndFound")
	}
}
