//
//  Tools.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 12/31/25.
//

import SwiftUI
import MapKit
import Charts
#if !targetEnvironment(macCatalyst)
import CoreNFC
#endif
import MeshtasticProtobufs
import OSLog

@available(iOS 18, *)
struct Tools: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context

	#if !targetEnvironment(macCatalyst)
	@StateObject private var nfcReader = NFCReader()
	#endif

	var connectedNode: NodeInfoEntity? {
		if let num = accessoryManager.activeDeviceNum {
			return getNodeInfo(id: num, context: context)
		}
		return nil
	}

	var qrString: String {
		guard let connectedNode = connectedNode else {
			return ""
		}

		var contact = SharedContact()
		contact.nodeNum = UInt32(connectedNode.num)
		contact.user = connectedNode.toProto().user
		contact.manuallyVerified = true

		do {
			let contactString = try contact.serializedData().base64EncodedString()
			return "https://meshtastic.org/v/#" + contactString.base64ToBase64url()
		} catch {
			Logger.services.error("Error serializing contact: \(error)")
			return ""
		}
	}

	var body: some View {
		VStack {
			List {
				Section(header: Text("Create Node Contact NFC Tag")) {
					if let node = connectedNode {
						Text("Node Name: \(node.user?.longName ?? "Unknown".localized)")
						#if !targetEnvironment(macCatalyst)
						Button {
							nfcReader.scan(theActualData: qrString)
						} label: {
							Label("Write Contact to NFC Tag", systemImage: "tag")
						}
						.disabled(qrString.isEmpty)
						#endif
					}
				}
				Section(header: Text("RF Planning")) {
					NavigationLink(destination: RFSitePlanningTool()) {
						Label("RF Site Planner", systemImage: "antenna.radiowaves.left.and.right")
					}
				}
			}
		}
		.navigationTitle("Tools")
		.navigationBarTitleDisplayMode(.inline)
	}
}

@available(iOS 18, *)
private enum RFSitePlanningMode: String, CaseIterable, Identifiable {
	case coverage
	case pointToPoint

	var id: String { rawValue }

	var title: String {
		switch self {
		case .coverage:
			return "Coverage"
		case .pointToPoint:
			return "Point to Point"
		}
	}
}

@available(iOS 18, *)
private enum RFSitePlanningColormap: String, CaseIterable, Identifiable {
	case plasma
	case viridis

	var id: String { rawValue }

	var title: String {
		switch self {
		case .plasma:
			return "Plasma"
		case .viridis:
			return "Viridis"
		}
	}
}

@available(iOS 18, *)
private struct RFSitePlanningTool: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@ObservedObject private var mapDataManager = MapDataManager.shared

	@AppStorage("mapOverlaysEnabled") private var mapOverlaysEnabled = false
	@AppStorage("mapOverlayOpacity") private var mapOverlayOpacity = GeoJSONOverlayManager.defaultOpacity
	@AppStorage("sitePlannerCoverageTxHeightMeters") private var txHeightMeters = 2.0
	@AppStorage("sitePlannerCoverageRxHeightMeters") private var rxHeightMeters = 1.0
	@AppStorage("sitePlannerCoverageRadiusKilometers") private var radiusKilometers = 30.0
	@AppStorage("sitePlannerCoverageHighResolution") private var highResolution = false
	@AppStorage("sitePlannerCoverageTxGainDbi") private var txGainDbi = 2.0
	@AppStorage("sitePlannerCoverageSystemLossDb") private var systemLossDb = 2.0
	@AppStorage("sitePlannerCoverageOverlayOpacity") private var overlayOpacity = 0.45
	@AppStorage("sitePlannerCoverageColormap") private var colormap = "plasma"
	@AppStorage("sitePlannerCoverageTxPowerDbm") private var txPowerDbm = 20.0
	@AppStorage("sitePlannerCoverageRxGainDbi") private var rxGainDbi = 2.0
	@AppStorage("sitePlannerCoverageFrequencyMHz") private var frequencyMHz = 907.0
	@AppStorage("sitePlannerCoverageSignalThresholdDbm") private var signalThresholdDbm = -130.0

	@State private var position = MapCameraPosition.automatic
	@State private var mapCenterCoordinate: CLLocationCoordinate2D?
	@State private var mode: RFSitePlanningMode = .coverage
	@State private var coverageCoordinate: CLLocationCoordinate2D?
	@State private var linkStartCoordinate: CLLocationCoordinate2D?
	@State private var linkEndCoordinate: CLLocationCoordinate2D?
	@State private var linkResult: SitePlannerPointToPointResult?
	@State private var presentedLinkResult: SitePlannerPointToPointResult?
	@State private var generatedOverlayIDs: Set<UUID> = []
	@State private var isGeneratingCoverage = false
	@State private var isAnalyzingLink = false
	@State private var isShowingSettings = false
	@State private var alertTitle = ""
	@State private var alertMessage = ""
	@State private var isShowingAlert = false

	private var activeDeviceCoordinate: CLLocationCoordinate2D? {
		guard let num = accessoryManager.activeDeviceNum else { return nil }
		return getNodeInfo(id: num, context: context)?.latestPosition?.nodeCoordinate
	}

	private var linkLineColor: Color {
		guard let result = linkResult else { return .accentColor }
		if !result.linkMeetsThreshold {
			return .red
		}
		if !result.hasDirectLineOfSight || !result.hasFresnelClearance {
			return .orange
		}
		return .green
	}

	var body: some View {
		ZStack {
			MapReader { reader in
				Map(position: $position) {
					RFSitePlanningOverlayContent(enabledOverlayConfigs: generatedOverlayIDs)
					mapAnnotations
					linkOverlay
				}
				.mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
				.mapControls {
					MapScaleView()
					MapPitchToggle()
					MapUserLocationButton()
					MapCompass()
				}
				.onMapCameraChange(frequency: .onEnd) { context in
					mapCenterCoordinate = context.camera.centerCoordinate
				}
				.simultaneousGesture(
					SpatialTapGesture(coordinateSpace: .local)
						.onEnded { value in
							guard let coordinate = reader.convert(value.location, from: .local) else { return }
							handleMapTap(coordinate)
						}
				)
				.ignoresSafeArea(.container, edges: [.top, .horizontal])
			}
			centerTarget
				.allowsHitTesting(false)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			plannerFooter
		}
		.navigationTitle("RF Site Planner")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar(.hidden, for: .tabBar)
		.toolbar {
			ToolbarItemGroup(placement: .topBarTrailing) {
				NavigationLink(destination: MapDataFiles()) {
					Image(systemName: "folder")
				}
				Button {
					isShowingSettings = true
				} label: {
					Image(systemName: "slider.horizontal.3")
				}
			}
		}
		.sheet(isPresented: $isShowingSettings) {
			RFSitePlanningSettingsSheet(
				txHeightMeters: $txHeightMeters,
				rxHeightMeters: $rxHeightMeters,
				radiusKilometers: $radiusKilometers,
				highResolution: $highResolution,
				overlayOpacity: $overlayOpacity,
				colormap: $colormap,
				txPowerDbm: $txPowerDbm,
				txGainDbi: $txGainDbi,
				rxGainDbi: $rxGainDbi,
				systemLossDb: $systemLossDb,
				frequencyMHz: $frequencyMHz,
				signalThresholdDbm: $signalThresholdDbm
			)
		}
		.sheet(item: $presentedLinkResult) { result in
			RFSitePlanningLinkResultSheet(result: result)
		}
		.alert(alertTitle, isPresented: $isShowingAlert) {
			Button("Ok") { }
		} message: {
			Text(alertMessage)
		}
		.onAppear {
			mapDataManager.initialize()
			if let coordinate = activeDeviceCoordinate ?? LocationsHandler.currentPreciseLocation {
				mapCenterCoordinate = coordinate
				position = .camera(MapCamera(centerCoordinate: coordinate, distance: 25_000))
			}
		}
	}

	private var centerTarget: some View {
		Image(systemName: "scope")
			.font(.title3.weight(.medium))
			.foregroundStyle(.primary)
			.shadow(color: .black.opacity(0.25), radius: 2)
			.accessibilityHidden(true)
	}

	@MapContentBuilder
	private var mapAnnotations: some MapContent {
		if mode == .coverage, let coverageCoordinate {
			Marker("Coverage Source", systemImage: "antenna.radiowaves.left.and.right", coordinate: coverageCoordinate)
				.tint(Color.accentColor)
		}

		if mode == .pointToPoint {
			if let linkStartCoordinate {
				Marker("Transmitter", systemImage: "arrow.up.right.circle.fill", coordinate: linkStartCoordinate)
					.tint(.blue)
			}

			if let linkEndCoordinate {
				Marker("Receiver", systemImage: "arrow.down.left.circle.fill", coordinate: linkEndCoordinate)
					.tint(.purple)
			}

			if let obstructionCoordinate {
				Marker("Blocking Terrain", systemImage: "mountain.2.fill", coordinate: obstructionCoordinate)
					.tint(.red)
			}
		}
	}

	@MapContentBuilder
	private var linkOverlay: some MapContent {
		if let linkStartCoordinate, let linkEndCoordinate {
			MapPolyline(coordinates: [linkStartCoordinate, linkEndCoordinate])
				.stroke(linkLineColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
		}
	}

	private var obstructionCoordinate: CLLocationCoordinate2D? {
		guard let result = linkResult else { return nil }
		let obstruction = result.directObstruction ?? result.fresnelObstruction
		guard let obstruction, result.distanceKm > 0 else { return nil }
		let fraction = min(1.0, max(0.0, obstruction.distanceKm / result.distanceKm))
		return CLLocationCoordinate2D(
			latitude: result.sourceLat + (result.destinationLat - result.sourceLat) * fraction,
			longitude: result.sourceLon + (result.destinationLon - result.sourceLon) * fraction
		)
	}

	private var plannerFooter: some View {
		VStack(spacing: 0) {
			Divider()
			VStack(alignment: .leading, spacing: 10) {
				Picker("Mode", selection: $mode) {
					ForEach(RFSitePlanningMode.allCases) { mode in
						Text(mode.title).tag(mode)
					}
				}
				.pickerStyle(.segmented)

				switch mode {
				case .coverage:
					coverageControls
				case .pointToPoint:
					pointToPointControls
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
		}
		.background(.bar)
	}

	private var coverageControls: some View {
		VStack(alignment: .leading, spacing: 8) {
			selectionRow("Source", value: Self.coordinateString(coverageCoordinate))
			HStack(spacing: 8) {
				Button {
					setPointFromMapCenter()
				} label: {
					Label("Set Source", systemImage: "scope")
				}
				.buttonStyle(.bordered)
				.disabled(mapCenterCoordinate == nil)

				Button {
					generateCoverage()
				} label: {
					Label(isGeneratingCoverage ? "Generating" : "Generate", systemImage: "antenna.radiowaves.left.and.right")
				}
				.buttonStyle(.borderedProminent)
				.disabled(coverageCoordinate == nil || isGeneratingCoverage)

				if isGeneratingCoverage {
					ProgressView()
				}
			}
			Text("\(Self.integerString(radiusKilometers)) km, \(Self.integerString(frequencyMHz)) MHz, \(Self.integerString(signalThresholdDbm)) dBm threshold")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}

	private var pointToPointControls: some View {
		VStack(alignment: .leading, spacing: 8) {
			selectionRow("Transmitter", value: Self.coordinateString(linkStartCoordinate))
			selectionRow("Receiver", value: Self.coordinateString(linkEndCoordinate))

			if let linkResult {
				HStack {
					Label(
						linkResult.linkMeetsThreshold ? "Meets threshold" : "Below threshold",
						systemImage: linkResult.linkMeetsThreshold ? "checkmark.circle.fill" : "xmark.circle.fill"
					)
					.foregroundStyle(linkResult.linkMeetsThreshold ? .green : .red)

					Spacer()

					Button("View Profile") {
						presentedLinkResult = linkResult
					}
					.buttonStyle(.bordered)
				}
				.font(.subheadline)
			}

			HStack(spacing: 8) {
				Button {
					setPointFromMapCenter()
				} label: {
					Label(centerSetButtonTitle, systemImage: "scope")
				}
				.buttonStyle(.bordered)
				.disabled(mapCenterCoordinate == nil)

				Button {
					analyzeLink()
				} label: {
					Label(isAnalyzingLink ? "Analyzing" : "Analyze", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
				}
				.buttonStyle(.borderedProminent)
				.disabled(linkStartCoordinate == nil || linkEndCoordinate == nil || isAnalyzingLink)

				Button("Clear") {
					linkStartCoordinate = nil
					linkEndCoordinate = nil
					linkResult = nil
				}
				.buttonStyle(.bordered)

				if isAnalyzingLink {
					ProgressView()
				}
			}
		}
	}

	private var centerSetButtonTitle: String {
		if linkStartCoordinate == nil || linkEndCoordinate != nil {
			return "Set TX"
		}
		return "Set RX"
	}

	private func selectionRow(_ title: String, value: String) -> some View {
		HStack(alignment: .firstTextBaseline) {
			Text(title)
			Spacer(minLength: 12)
			Text(value)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
		}
		.font(.subheadline)
	}

	private func setPointFromMapCenter() {
		guard let mapCenterCoordinate else { return }
		handleMapTap(mapCenterCoordinate)
	}

	private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
		switch mode {
		case .coverage:
			coverageCoordinate = coordinate
		case .pointToPoint:
			if linkStartCoordinate == nil || linkEndCoordinate != nil {
				linkStartCoordinate = coordinate
				linkEndCoordinate = nil
				linkResult = nil
			} else {
				linkEndCoordinate = coordinate
				linkResult = nil
			}
		}
	}

	private func generateCoverage() {
		guard let coverageCoordinate else { return }
		let payload = coverageRequest(at: coverageCoordinate)
		let overlayName = "RF Coverage \(Self.shortCoordinateString(coverageCoordinate))"

		mapDataManager.initialize()
		isGeneratingCoverage = true
		Task {
			do {
				let rawData = try await NativeSitePlannerCoverageClient(
					contourMaxDimension: highResolution ? 900 : 640,
					contourPolygonLimit: highResolution ? 4_500 : 2_500
				)
				.generateContours(request: payload)
				let data = try SitePlannerCoverageClient.annotatedCoverageFeatureCollectionData(
					from: rawData,
					request: payload,
					overlayOpacity: overlayOpacity
				)
				let metadata = try await MapDataManager.shared.processGeoJSONData(
					data,
					originalName: overlayName,
					fileExtension: "geojson",
					makeActive: true
				)

				await MainActor.run {
					generatedOverlayIDs.insert(metadata.id)
					mapOverlaysEnabled = true
					isGeneratingCoverage = false
					presentAlert(
						title: "Coverage Generated",
						message: "Added \(metadata.overlayCount) RF bands for \(Self.shortCoordinateString(coverageCoordinate))."
					)
				}
			} catch {
				await MainActor.run {
					isGeneratingCoverage = false
					presentAlert(title: "Coverage Failed", message: error.localizedDescription)
				}
			}
		}
	}

	private func analyzeLink() {
		guard let linkStartCoordinate, let linkEndCoordinate else { return }
		isAnalyzingLink = true
		let request = SitePlannerPointToPointRequest(
			sourceLat: linkStartCoordinate.latitude,
			sourceLon: linkStartCoordinate.longitude,
			destinationLat: linkEndCoordinate.latitude,
			destinationLon: linkEndCoordinate.longitude,
			txHeight: txHeightMeters,
			txPower: txPowerDbm,
			txGain: txGainDbi,
			systemLoss: systemLossDb,
			frequencyMHz: frequencyMHz,
			rxHeight: rxHeightMeters,
			rxGain: rxGainDbi,
			signalThreshold: signalThresholdDbm,
			highResolution: highResolution
		)

		Task {
			do {
				let result = try await NativeSitePlannerPointToPointClient().analyze(request: request)
				await MainActor.run {
					linkResult = result
					presentedLinkResult = result
					isAnalyzingLink = false
				}
			} catch {
				await MainActor.run {
					isAnalyzingLink = false
					presentAlert(title: "Link Analysis Failed", message: error.localizedDescription)
				}
			}
		}
	}

	private func coverageRequest(at coordinate: CLLocationCoordinate2D) -> SitePlannerCoverageRequest {
		SitePlannerCoverageRequest(
			lat: coordinate.latitude,
			lon: coordinate.longitude,
			txHeight: txHeightMeters,
			txPower: txPowerDbm,
			txGain: txGainDbi,
			systemLoss: systemLossDb,
			frequencyMHz: frequencyMHz,
			rxHeight: rxHeightMeters,
			rxGain: rxGainDbi,
			signalThreshold: signalThresholdDbm,
			radius: radiusKilometers * 1_000.0,
			highResolution: highResolution,
			colormap: (RFSitePlanningColormap(rawValue: colormap) ?? .plasma).rawValue,
			minDbm: signalThresholdDbm
		)
	}

	private func presentAlert(title: String, message: String) {
		alertTitle = title
		alertMessage = message
		isShowingAlert = true
	}

	private static func coordinateString(_ coordinate: CLLocationCoordinate2D?) -> String {
		guard let coordinate else { return "Tap map or set from center" }
		return shortCoordinateString(coordinate)
	}

	private static func shortCoordinateString(_ coordinate: CLLocationCoordinate2D) -> String {
		String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
	}

	private static func integerString(_ value: Double) -> String {
		String(format: "%.0f", value)
	}

	private static func decimalString(_ value: Double) -> String {
		String(format: "%.1f", value)
	}
}

@available(iOS 18, *)
private struct RFSitePlanningOverlayContent: MapContent {
	let enabledOverlayConfigs: Set<UUID>
	@AppStorage("mapOverlayOpacity") private var mapOverlayOpacity = GeoJSONOverlayManager.defaultOpacity

	var body: some MapContent {
		let features = GeoJSONOverlayManager.shared.loadStyledFeaturesForConfigs(enabledOverlayConfigs)
		let opacityMultiplier = GeoJSONOverlayManager.normalizedOpacity(mapOverlayOpacity)

		ForEach(features) { styledFeature in
			let feature = styledFeature.feature
			if feature.geometry.type == "Point" {
				if let coordinate = feature.geometry.coordinates.toCoordinate() {
					Annotation(feature.name, coordinate: coordinate) {
						Circle()
							.fill(styledFeature.fillColor(opacityMultiplier: opacityMultiplier))
							.stroke(styledFeature.strokeColor(opacityMultiplier: opacityMultiplier), style: styledFeature.strokeStyle)
							.frame(width: feature.markerRadius * 2, height: feature.markerRadius * 2)
					}
				}
			} else if feature.geometry.type == "LineString" {
				if let overlay = styledFeature.createOverlay() as? MKPolyline {
					MapPolyline(overlay)
						.stroke(styledFeature.strokeColor(opacityMultiplier: opacityMultiplier), style: styledFeature.strokeStyle)
				}
			} else if feature.geometry.type == "Polygon" || feature.geometry.type == "MultiPolygon" {
				ForEach(styledFeature.createOverlays()) { renderableOverlay in
					if let overlay = renderableOverlay.overlay as? MKPolygon {
						MapPolygon(overlay)
							.foregroundStyle(styledFeature.fillColor(opacityMultiplier: opacityMultiplier))
							.stroke(styledFeature.strokeColor(opacityMultiplier: opacityMultiplier), style: styledFeature.strokeStyle)
					}
				}
			}
		}
	}
}

@available(iOS 18, *)
private struct RFSitePlanningSettingsSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Binding var txHeightMeters: Double
	@Binding var rxHeightMeters: Double
	@Binding var radiusKilometers: Double
	@Binding var highResolution: Bool
	@Binding var overlayOpacity: Double
	@Binding var colormap: String
	@Binding var txPowerDbm: Double
	@Binding var txGainDbi: Double
	@Binding var rxGainDbi: Double
	@Binding var systemLossDb: Double
	@Binding var frequencyMHz: Double
	@Binding var signalThresholdDbm: Double

	private var maximumRadiusKilometers: Double {
		highResolution ? 70.0 : 150.0
	}

	var body: some View {
		NavigationStack {
			Form {
				Section(header: Text("Coverage")) {
					Toggle("High Detail", isOn: $highResolution)
						.tint(.accentColor)
					LabeledContent("Range", value: "\(Self.integerString(radiusKilometers)) km")
					Slider(value: $radiusKilometers, in: 1.0...maximumRadiusKilometers, step: 1.0)
					LabeledContent("Overlay Opacity", value: "\(Self.percentString(overlayOpacity))")
					Slider(value: $overlayOpacity, in: 0.15...0.80, step: 0.05)
					Picker("Color Ramp", selection: $colormap) {
						ForEach(RFSitePlanningColormap.allCases) { ramp in
							Text(ramp.title).tag(ramp.rawValue)
						}
					}
				}

				Section(header: Text("Heights Above Ground")) {
					Stepper(value: $txHeightMeters, in: 0.5...60.0, step: 0.5) {
						LabeledContent("Transmitter", value: Self.meterString(txHeightMeters))
					}
					Stepper(value: $rxHeightMeters, in: 0.5...60.0, step: 0.5) {
						LabeledContent("Receiver", value: Self.meterString(rxHeightMeters))
					}
				}

				Section(header: Text("RF Details")) {
					Stepper(value: $frequencyMHz, in: 400.0...2_500.0, step: 1.0) {
						LabeledContent("Frequency", value: "\(Self.integerString(frequencyMHz)) MHz")
					}
					Stepper(value: $txPowerDbm, in: 0.0...33.0, step: 1.0) {
						LabeledContent("Transmit Power", value: "\(Self.integerString(txPowerDbm)) dBm")
					}
					Stepper(value: $txGainDbi, in: -3.0...15.0, step: 0.5) {
						LabeledContent("TX Antenna Gain", value: "\(Self.decimalString(txGainDbi)) dBi")
					}
					Stepper(value: $rxGainDbi, in: -3.0...15.0, step: 0.5) {
						LabeledContent("RX Antenna Gain", value: "\(Self.decimalString(rxGainDbi)) dBi")
					}
					Stepper(value: $systemLossDb, in: 0.0...10.0, step: 0.5) {
						LabeledContent("System Loss", value: "\(Self.decimalString(systemLossDb)) dB")
					}
					Stepper(value: $signalThresholdDbm, in: -145.0 ... -100.0, step: 1.0) {
						LabeledContent("Receiver Threshold", value: "\(Self.integerString(signalThresholdDbm)) dBm")
					}
				}
			}
			.navigationTitle("RF Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						dismiss()
					}
				}
			}
			.onChange(of: highResolution) { _, _ in
				radiusKilometers = min(maximumRadiusKilometers, max(1.0, radiusKilometers))
			}
		}
		.presentationDetents([.medium, .large])
		.presentationDragIndicator(.visible)
	}

	private static func integerString(_ value: Double) -> String {
		String(format: "%.0f", value)
	}

	private static func decimalString(_ value: Double) -> String {
		String(format: "%.1f", value)
	}

	private static func meterString(_ value: Double) -> String {
		value < 10.0 ? String(format: "%.1f m", value) : String(format: "%.0f m", value)
	}

	private static func percentString(_ value: Double) -> String {
		String(format: "%.0f%%", value * 100.0)
	}
}

@available(iOS 18, *)
private struct RFSitePlanningLinkResultSheet: View {
	let result: SitePlannerPointToPointResult

	private var chartSamples: [SitePlannerPointToPointSample] {
		let maximumSamples = 240
		guard result.samples.count > maximumSamples else { return result.samples }
		let step = max(1, result.samples.count / maximumSamples)
		var samples = stride(from: 0, to: result.samples.count, by: step).map { result.samples[$0] }
		if samples.last != result.samples.last, let last = result.samples.last {
			samples.append(last)
		}
		return samples
	}

	var body: some View {
		NavigationStack {
			Form {
				Section(header: Text("Prediction")) {
					Label(
						result.linkMeetsThreshold ? "Link meets receiver threshold" : "Link is below receiver threshold",
						systemImage: result.linkMeetsThreshold ? "checkmark.circle.fill" : "xmark.circle.fill"
					)
					.foregroundStyle(result.linkMeetsThreshold ? .green : .red)
					LabeledContent("Distance", value: "\(Self.decimalString(result.distanceKm)) km")
					LabeledContent("Path Loss", value: "\(Self.decimalString(result.lossDb)) dB")
					LabeledContent("Predicted Signal", value: "\(Self.decimalString(result.signalDbm)) dBm")
					LabeledContent("Link Margin", value: "\(Self.decimalString(result.linkMarginDb)) dB")
					LabeledContent("Azimuth", value: "\(Self.decimalString(result.azimuthDegrees)) deg")
				}

				Section(header: Text("Clearance")) {
					LabeledContent("Direct LOS", value: result.hasDirectLineOfSight ? "Clear" : "Blocked")
					LabeledContent("60% Fresnel", value: result.hasFresnelClearance ? "Clear" : "Blocked")
					if let obstruction = result.directObstruction ?? result.fresnelObstruction {
						LabeledContent("Blocking Point", value: "\(Self.decimalString(obstruction.distanceKm)) km")
						LabeledContent("Direct Clearance", value: "\(Self.decimalString(obstruction.directClearanceMeters)) m")
						LabeledContent("Fresnel Clearance", value: "\(Self.decimalString(obstruction.fresnel60ClearanceMeters)) m")
					}
				}

				Section(header: Text("Terrain Profile")) {
					Chart {
						ForEach(Array(chartSamples.enumerated()), id: \.offset) { _, sample in
							LineMark(
								x: .value("Distance", sample.distanceKm),
								y: .value("Elevation", sample.groundElevationMeters),
								series: .value("Series", "Terrain")
							)
							.foregroundStyle(.brown)
							LineMark(
								x: .value("Distance", sample.distanceKm),
								y: .value("Elevation", sample.sightLineElevationMeters),
								series: .value("Series", "Line of Sight")
							)
							.foregroundStyle(.blue)
							LineMark(
								x: .value("Distance", sample.distanceKm),
								y: .value("Elevation", sample.fresnel60ElevationMeters),
								series: .value("Series", "60% Fresnel")
							)
							.foregroundStyle(.orange)
						}
						if let obstruction = result.directObstruction ?? result.fresnelObstruction {
							PointMark(
								x: .value("Distance", obstruction.distanceKm),
								y: .value("Elevation", obstruction.groundElevationMeters)
							)
							.foregroundStyle(.red)
							.symbolSize(80)
						}
					}
					.chartXAxisLabel("Distance (km)")
					.chartYAxisLabel("Elevation (m)")
					.frame(height: 260)
				}
			}
			.navigationTitle("Link Profile")
			.navigationBarTitleDisplayMode(.inline)
		}
		.presentationDetents([.medium, .large])
		.presentationDragIndicator(.visible)
	}

	private static func decimalString(_ value: Double) -> String {
		String(format: "%.1f", value)
	}
}

@available(iOS 18, *)
#Preview {
	Tools()
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}

#if !targetEnvironment(macCatalyst)
@available(iOS 18, *)
final class NFCReader: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {

	private let logger = Logger(subsystem: "org.meshtastic.app", category: "NFC")
	private var payloadString = ""
	private var session: NFCNDEFReaderSession?

	func scan(theActualData: String) {
		payloadString = theActualData

		session = NFCNDEFReaderSession(
			delegate: self,
			queue: nil,
			invalidateAfterFirstRead: false
		)

		session?.alertMessage = "Hold your iPhone near the NFC tag."
		session?.begin()
	}

	func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
		logger.debug("NFC session became active")
	}

	func readerSession(_ session: NFCNDEFReaderSession,
	                   didInvalidateWithError error: Error) {
		logger.error("NFC session invalidated: \(error.localizedDescription)")
	}

	func readerSession(_ session: NFCNDEFReaderSession,
	                   didDetectNDEFs messages: [NFCNDEFMessage]) {
	}

	func readerSession(_ session: NFCNDEFReaderSession,
	                   didDetect tags: [NFCNDEFTag]) {

		guard tags.count == 1, let tag = tags.first else {
			session.alertMessage = "More than one tag detected. Please present only one."
			DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
				session.restartPolling()
			}
			return
		}

		session.connect(to: tag) { error in
			if let error {
				self.logger.error("Failed to connect to tag: \(error.localizedDescription)")
				session.alertMessage = "Failed to connect to tag."
				session.invalidate()
				return
			}

			tag.queryNDEFStatus { status, capacity, error in
				if let error {
					self.logger.error("Failed to query NDEF status: \(error.localizedDescription)")
					session.alertMessage = "Failed to read tag."
					session.invalidate()
					return
				}
				self.logger.debug("Tag NDEF status: \(String(describing: status)), capacity: \(capacity) bytes")

				switch status {
				case .notSupported:
					self.logger.error("Tag does not support NDEF")
					session.alertMessage = "Tag does not support NDEF."
					session.invalidate()

				case .readOnly:
					self.logger.error("Tag is read-only")
					session.alertMessage = "Tag is read-only."
					session.invalidate()

				case .readWrite:
					guard let payload =
						NFCNDEFPayload.wellKnownTypeURIPayload(
							string: self.payloadString
						) else {
						self.logger.error("Invalid NDEF payload")
						session.alertMessage = "Invalid payload."
						session.invalidate()
						return
					}

					let message = NFCNDEFMessage(records: [payload])

					guard message.length <= capacity else {
						self.logger.error("Payload (\(message.length) bytes) exceeds tag capacity (\(capacity) bytes)")
						session.alertMessage = "Tag too small to hold contact data."
						session.invalidate()
						return
					}

					tag.writeNDEF(message) { error in
						if let error {
							self.logger.error("Failed to write NDEF: \(error.localizedDescription)")
							session.alertMessage = "Failed to write tag."
						} else {
							self.logger.info("Successfully wrote NFC tag")
							session.alertMessage = "NFC tag written successfully."
						}
						session.invalidate()
					}

				@unknown default:
					self.logger.error("Unsupported NDEF status")
					session.alertMessage = "Unsupported tag status."
					session.invalidate()
				}
			}
		}
	}
}
#endif
