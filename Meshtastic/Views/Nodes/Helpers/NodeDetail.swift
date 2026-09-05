/*
 Abstract:
 A view showing the details for a node.
 */

import SwiftUI
import Foundation
import WeatherKit
import MapKit
import CoreLocation
import OSLog
@preconcurrency import SwiftData
import MeshtasticProtobufs

extension NSNotification.Name {
	static let nodeLogAvailabilityDidChange = NSNotification.Name("nodeLogAvailabilityDidChange")
}

private struct NodeDetailLogAvailability {
	var hasDeviceMetrics = false
	var hasPositions = false
	var hasEnvironmentMetrics = false
	var hasAirQualityMetrics = false
	var hasTraceRoutes = false
	var hasPowerMetrics = false
	var hasDetectionSensorMetrics = false
	var hasPax = false
}

struct NodeDetail: View {
	private let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	private let nodeDetailScrollContentTopMargin: CGFloat = 0
	private static let relativeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter
	}()
	var modemPreset: ModemPresets = ModemPresets(
		rawValue: UserDefaults.modemPreset
	) ?? ModemPresets.longFast
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var router: Router
	@State private var showingShutdownConfirm: Bool = false
	@State private var showingRebootConfirm: Bool = false
	@State private var showingSetTimeConfirm: Bool = false
	@State private var showingFactoryResetConfirm: Bool = false
	@State private var showingNodeDBResetConfirm: Bool = false
	@State private var isPerformingAdminAction: Bool = false
	@State private var adminErrorMessage: String?
	@State private var pendingAdminTarget: RemoteAdminActionTarget?
	@State private var dateFormatRelative: Bool = true
	@Bindable	var node: NodeInfoEntity
	private let nodeNum: Int64
	@Query private var users: [UserEntity]
	private let showMapLink: Bool
	@State private var latestPosition: PositionEntity?
	@State private var latestDeviceMetrics: TelemetryEntity?
	@State private var latestEnvironmentMetrics: TelemetryEntity?
	@State private var latestAirQualityMetrics: TelemetryEntity?
	@State private var airQualityNowCastAQI: Int?
	@State private var latestPowerMetrics: TelemetryEntity?
	@State private var logAvailability = NodeDetailLogAvailability()
	@State private var showingShareContactQR = false
	@State private var remoteAdminState: RemoteAdminSessionState = .stale
	@State private var remoteAdminAttemptID: UUID?
	@State private var remoteSettingsDestination: RemoteAdminSettingsDestination?

	init(node: NodeInfoEntity, nodeNum: Int64, showMapLink: Bool = true) {
		self.node = node
		self.nodeNum = nodeNum
		self.showMapLink = showMapLink
		_users = Query(filter: #Predicate<UserEntity> { $0.num == nodeNum })
	}

	/// The currently BLE-connected (or remotely administered) node, derived reactively
	/// from accessoryManager.activeDeviceNum so it stays current if the connection changes.
	private var connectedNode: NodeInfoEntity? {
		guard let num = accessoryManager.activeDeviceNum else { return nil }
		return getNodeInfo(id: num, context: context)
	}
	/// Resolve the current user independently of `node.user`. A node detail can remain in a
	/// navigation stack after a store reset, where that relationship can retain faulted backing
	/// data even though the user query has already removed the deleted row.
	private var currentUser: UserEntity? {
		guard let user = users.first,
			user.modelContext != nil,
			!user.isDeleted
		else { return nil }
		return user
	}
	private var connectedUser: UserEntity? {
		guard let num = accessoryManager.activeDeviceNum else { return nil }
		let descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.num == num })
		guard let user = try? context.fetch(descriptor).first,
			user.modelContext != nil,
			!user.isDeleted
		else { return nil }
		return user
	}
	private var shareContactNode: NodeInfo {
		var shareNode = NodeInfo()
		shareNode.num = UInt32(nodeNum)
		if let currentUser {
			shareNode.user = currentUser.toProto()
		}
		return shareNode
	}
	private var administrationUserPair: (fromUser: UserEntity, toUser: UserEntity)? {
		guard let fromUser = connectedUser,
			  let toUser = currentUser else {
			return nil
		}
		return (fromUser, toUser)
	}
	private var currentAdminTarget: RemoteAdminActionTarget? {
		guard let radioNum = accessoryManager.activeDeviceNum,
			  let connection = accessoryManager.activeConnection?.connection else { return nil }
		return RemoteAdminActionTarget(
			nodeNum: nodeNum,
			name: currentUser?.displayLongName ?? "Unknown",
			radioNum: radioNum,
			connectionID: ObjectIdentifier(connection))
	}
	/// The status row opens the status message editor for the connected node, or for a remote
	/// node we have successfully administered before. Firmware 2.8+ in both cases: the
	/// connected node via `supportsStatusMessage`, a remote target additionally via its own
	/// reported metadata (permissive when unknown, matching the house capability gates).
	private var canEditStatusMessage: Bool {
		guard accessoryManager.supportsStatusMessage else { return false }
		if accessoryManager.activeDeviceNum == nodeNum { return true }
		return node.hasBeenAdministered && node.firmwareSupportsStatusMessage
	}
	@State var showingCompassSheet = false
	@State private var nodeForDisplayNameEdit: NodeInfoEntity?
	@State private var nodeForStatusMessageEdit: NodeInfoEntity?
	/// Bumped whenever a local display name is set/cleared to force this view to re-render —
	/// NodeDisplayNameStore is plain UserDefaults, not a SwiftData/@Bindable property, so nothing
	/// else here would pick up the change.
	@State private var displayNameRefresh = 0

	var body: some View {
		if node.modelContext != nil, !node.isDeleted {
			ScrollViewReader { scrollView in
				Color.clear
					.frame(height: 0) // Ensure it has no height
					.id("topOfList")
					nodeDetailList
						.sheet(isPresented: $showingCompassSheet) {
							CompassView(waypointLocation: latestPosition?.nodeCoordinate ?? nil, waypointLongName: currentUser?.displayLongName, waypointShortName: currentUser?.shortName, color: Color(UIColor(hex: UInt32(nodeNum))))
						}
						.sheet(isPresented: $showingShareContactQR) {
							ShareContactQRDialog(
								manuallyVerified: nodeNum == accessoryManager.activeDeviceNum,
								node: shareContactNode
							)
						}
						.displayNameAlert(node: $nodeForDisplayNameEdit)
						.statusMessageAlert(node: $nodeForStatusMessageEdit)
					.onReceive(NotificationCenter.default.publisher(for: NodeDisplayNameStore.didChangeNotification)) { notification in
						// Scoped to this node: the notification's object is unconditionally `nil`
						// otherwise, and `displayNameRefresh` drives `.id()` below (which recreates
						// the list and re-triggers its scroll-to-top onAppear) -- renaming an
						// unrelated node elsewhere must not yank this detail view back to the top.
						guard notification.object as? Int64 == nodeNum else { return }
						displayNameRefresh += 1
					}
					.onAppear {
						refreshNodeSummary()
						scrollView.scrollTo("topOfList", anchor: .top)
					}
						.onChange(of: node.lastHeard) {
							refreshNodeSummary()
						}
						.onChange(of: accessoryManager.activeDeviceNum) { _, _ in
							remoteSettingsDestination = nil
							remoteAdminAttemptID = nil
							if !accessoryManager.isConnected {
								remoteAdminState = .stale
							}
						}
						.onChange(of: accessoryManager.isConnected) { _, connected in
							if !connected {
								remoteSettingsDestination = nil
								remoteAdminAttemptID = nil
								remoteAdminState = .stale
							}
						}
						.onReceive(NotificationCenter.default.publisher(for: .nodeLogAvailabilityDidChange)) { notification in
							guard notification.object as? Int64 == nodeNum else { return }
							refreshNodeSummary()
						}
						.contentMargins(.top, nodeDetailScrollContentTopMargin, for: .scrollContent)
						.task(id: remoteAdminAttemptID) {
							guard remoteAdminAttemptID != nil else { return }
							await establishRemoteAdminSession()
						}
					.onChange(of: accessoryManager.activeConnection.map { ObjectIdentifier($0.connection) }) { _, connectionID in
						if let destination = remoteSettingsDestination, destination.connectionID != connectionID {
							remoteSettingsDestination = nil
						}
					}
					.navigationDestination(isPresented: Binding(
						get: { remoteSettingsDestination != nil },
						set: { if !$0 { remoteSettingsDestination = nil } }
					)) {
						if let destination = remoteSettingsDestination {
							Settings(remoteNodeNum: destination.nodeNum)
								.disabled(!destination.isCurrent(
									radioNum: accessoryManager.activeDeviceNum,
									connectionID: accessoryManager.activeConnection.map { ObjectIdentifier($0.connection) },
									isConnected: accessoryManager.isConnected))
						}
					}
					.onChange(of: nodeNum) { _, _ in
						remoteSettingsDestination = nil
						remoteAdminAttemptID = nil
					}
					.navigationTitle(String((currentUser?.displayLongName ?? "Unknown".localized).addingVariationSelectors))
					.navigationBarTitleDisplayMode(.inline)
					.id(displayNameRefresh)
			}
		} else {
			// Node was deleted or detached (e.g. after a database reset / node switch).
			// Reading any attribute on a faulted @Model traps during render, so render
			// nothing — the navigation stack pops this detail as its data source updates.
			Color.clear
		}
	}

	@ViewBuilder
	private var nodeDetailList: some View {
		List {
			NodeInfoItem(nodeNum: nodeNum)
				.id(nodeNum)
			nodeSection
			environmentSection
			airQualitySection
			powerSection
			logsSection
			actionsSection
			administrationSection
		}
		.listStyle(.insetGrouped)
	}

	// MARK: - Node Section

	@ViewBuilder
	private var nodeSection: some View {
		Section("Node") {
			HStack(alignment: .center) {
				Spacer()
				CircleText(
					text: currentUser?.shortName ?? "?",
					color: Color(UIColor(hex: UInt32(nodeNum))),
					circleSize: 75
				)
				if node.snr != 0 && !node.viaMqtt && node.hopsAway == 0 {
					Spacer()
					VStack {
						let signalStrength = getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: modemPreset, noiseFloor: connectedNode?.recentNoiseFloor)
						LoRaSignalStrengthIndicator(signalStrength: signalStrength)
						Text("Signal \(signalStrength.description)").font(.footnote)
						Text("SNR \(String(format: "%.2f", node.snr))dB")
							.foregroundColor(signalStrength.color)
							.font(.caption)
						Text("RSSI \(node.rssi)dB")
							.foregroundColor(getRssiColor(rssi: node.rssi))
							.font(.caption)
					}
					.accessibilityElement(children: .combine)
				}
				if latestDeviceMetrics != nil {
					Spacer()
					BatteryGauge(node: node)
				}
				Spacer()
			}
			.accessibilityElement(children: .combine)
			.listRowSeparator(.hidden)
			if let user = currentUser {
				if !user.keyMatch {
					Label {
						VStack(alignment: .leading) {
							Text("Public Key Mismatch")
								.font(.title3)
								.foregroundStyle(.red)
							Text("Verify who you are messaging with by comparing public keys in person or over the phone. The most recent public key for this node does not match the previously recorded key. You can delete the node and let it exchange keys again if the key change was due to a factory reset or other intentional action but this also may indicate a more serious security problem.")
								.foregroundStyle(.secondary)
								.font(.callout)
						}
						.accessibilityElement(children: .combine)
					} icon: {
						Image(systemName: "key.slash.fill")
							.symbolRenderingMode(.multicolor)
							.foregroundStyle(.red)
					}
				}
			}
			// Local-only display name shown instead of the device long name. Never leaves this
			// device (not sent over the mesh, not exported/shared) — see NodeDisplayNameStore.
			Button {
				nodeForDisplayNameEdit = node
			} label: {
				HStack {
					Label {
						Text("Name")
					} icon: {
						Image(systemName: "person.crop.circle")
							.symbolRenderingMode(.hierarchical)
					}
					Spacer()
					Text(currentUser?.displayLongName ?? "—")
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}
			.accessibilityElement(children: .combine)
			HStack {
				Label {
					Text("Node Number")
				} icon: {
					Image(systemName: "number")
						.symbolRenderingMode(.hierarchical)
				}
				Spacer()
				Text(String(nodeNum))
					.textSelection(.enabled)
			}
			.accessibilityElement(children: .combine)
			HStack {
				Label {
					Text("User Id")
				} icon: {
					Image(systemName: "person")
						.symbolRenderingMode(.multicolor)
				}
				Spacer()
				Text(nodeNum.toHex())
					.textSelection(.enabled)
			}
			.accessibilityElement(children: .combine)
			// Signed node = automatic trust, observed from the radio. Because NodeInfo is itself a signed
			// broadcast, the node's identity is verified by extension. Ordered above the public-key (has-key)
			// row so the section reads most-trusted-first. Affirmative only — never shown for unsigned nodes.
			if node.hasXeddsaSigned {
				HStack {
					Label {
						Text("Signed node")
					} icon: {
						Image(systemName: "checkmark.shield.fill")
							.foregroundColor(.green)
					}
					Spacer()
					Text("Verified automatically")
						.foregroundStyle(.secondary)
				}
				.accessibilityElement(children: .combine)
			}
			if let user = currentUser, user.keyMatch {
				let publicKey = nodeNum == accessoryManager.activeDeviceNum
				? node.securityConfig?.publicKey?.base64EncodedString() ?? ""
				: user.publicKey?.base64EncodedString() ?? ""
				HStack {
					Label {
						Text("Public Key")
					} icon: {
						Image(systemName: "lock.fill")
							.foregroundColor(.green)
					}
					Spacer()
					Button(action: {
						UIPasteboard.general.string = publicKey
					}) {
						HStack {
							Image(systemName: "key.horizontal.fill")
							Text("Copy")
						}
					}
				}
				.accessibilityElement(children: .combine)
			}
			if let metadata = node.metadata {
				HStack {
					Label {
						Text("Firmware Version")
					} icon: {
						Image(systemName: "memorychip")
							.symbolRenderingMode(.multicolor)
					}
					Spacer()
					Text(metadata.firmwareVersion ?? "Unknown".localized)
				}
				.accessibilityElement(children: .combine)
			}
			if let role = currentUser?.role, let deviceRole = DeviceRoles(rawValue: Int(role)) {
				HStack {
					Label {
						Text("Role")
					} icon: {
						Image(systemName: deviceRole.systemName)
							.symbolRenderingMode(.multicolor)
					}
					Spacer()
					Text(deviceRole.name)
				}
				.accessibilityElement(children: .combine)
			}
			// User-authored status broadcast by the node. Untrusted free text — rendered
			// verbatim as plain text, never markup. `Text(_: String)` does not parse markdown.
			// Detail has more room than the cards (design#115), so it shows the full
			// status rather than the 2-line card clamp — but still capped so a remote
			// node broadcasting newline-laden text (the 80-byte cap is only enforced on
			// the local save path) can't grow the row without bound.
			// For the connected node or an administered node the row is a button that opens
			// the same status editor as the node list context menu, and it stays visible
			// (with an em-dash) when no status is set. Read-only otherwise, and omitted
			// entirely when empty (no placeholder).
			if canEditStatusMessage {
				Button {
					nodeForStatusMessageEdit = node
				} label: {
					HStack(alignment: .top) {
						Label {
							Text("Status Message")
						} icon: {
							Image(systemName: NodeStatusStyle.glyph)
								.symbolRenderingMode(.hierarchical)
						}
						Spacer()
						Text(node.statusMessageDisplay ?? "—")
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.trailing)
							.lineLimit(6)
					}
				}
				.accessibilityElement(children: .combine)
			} else if let status = node.statusMessageDisplay {
				HStack(alignment: .top) {
					Label {
						Text("Status Message")
					} icon: {
						Image(systemName: NodeStatusStyle.glyph)
							.symbolRenderingMode(.hierarchical)
					}
					Spacer()
					Text(status)
						.multilineTextAlignment(.trailing)
						.lineLimit(6)
						.textSelection(.enabled)
				}
				.accessibilityElement(children: .combine)
			}
			if currentUser?.unmessagable ?? false {
				HStack {
					Label {
						Text("Messaging")
					} icon: {
						Image(systemName: "iphone.slash")
							.symbolRenderingMode(.multicolor)
					}
					Spacer()
					Text("Unmonitored")
				}
				.accessibilityElement(children: .combine)
			}
				if let dm = latestDeviceMetrics, let uptimeSeconds = dm.uptimeSeconds {
					HStack {
						Label {
							Text("\("Uptime".localized)")
					} icon: {
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.green)
							.symbolRenderingMode(.hierarchical)
					}
					Spacer()
					let now = Date.now
					let later = now + TimeInterval(uptimeSeconds)
					let uptime = (now..<later).formatted(.components(style: .narrow))
					Text(uptime)
						.textSelection(.enabled)
				}
				.accessibilityElement(children: .combine)
			}
			if let firstHeard = node.firstHeard, firstHeard.timeIntervalSince1970 > 0 && firstHeard < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
				HStack {
					Label {
						Text("First heard")
					} icon: {
						Image(systemName: "clock")
							.symbolRenderingMode(.multicolor)
					}
					Spacer()
					if dateFormatRelative, let text = Self.relativeFormatter.string(for: firstHeard) {
						Text(text)
							.textSelection(.enabled)
					} else {
						Text(firstHeard.formatted())
							.textSelection(.enabled)
					}
				}
				.accessibilityElement(children: .combine)
				.onTapGesture {
					dateFormatRelative.toggle()
				}
				.accessibilityAddTraits(.isButton)
				.accessibilityAction {
					dateFormatRelative.toggle()
				}
			}
			if let lastHeard = node.lastHeard, lastHeard.timeIntervalSince1970 > 0 && lastHeard < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
				HStack {
					Label {
						Text("Last heard")
					} icon: {
						Image(systemName: "clock.arrow.circlepath")
							.symbolRenderingMode(.multicolor)
					}
					Spacer()
					if dateFormatRelative, let text = Self.relativeFormatter.string(for: lastHeard) {
						if lastHeard.formatted() != "Unknown Age".localized {
							Text(text)
								.textSelection(.enabled)
						}
					} else {
						Text(lastHeard.formatted())
							.textSelection(.enabled)
					}
				}
				.accessibilityElement(children: .combine)
				.onTapGesture {
					dateFormatRelative.toggle()
				}
				.accessibilityAddTraits(.isButton)
				.accessibilityAction {
					dateFormatRelative.toggle()
				}
			}
		}
	}

	// MARK: - Environment Section

	@ViewBuilder
	private var environmentSection: some View {
		if latestPosition != nil && UserDefaults.environmentEnableWeatherKit
			|| hasDataForLatestEnvironmentMetrics(attributes: ["iaq", "temperature", "relativeHumidity", "barometricPressure", "windSpeed", "radiation", "weight", "Distance", "soilTemperature", "soilMoisture"]) {
			Section("Environment") {
				VStack(spacing: 0) {
					if latestEnvironmentMetrics == nil {
						LocalWeatherConditions(location: latestPosition?.nodeLocation)
					} else if let metrics = latestEnvironmentMetrics {
						VStack {
							if metrics.iaq ?? -1 > 0 {
								IndoorAirQuality(iaq: Int(metrics.iaq ?? 0), displayMode: .gradient)
									.padding(.vertical)
							}
							LazyVGrid(columns: gridItemLayout) {
								if let temperature = metrics.temperature?.shortFormattedTemperature() {
									WeatherConditionsCompactWidget(temperature: String(temperature), symbolName: "cloud.sun", description: "TEMP")
								}
								if let humidity = metrics.relativeHumidity {
									if let temperature = metrics.temperature {
										let dewPoint = calculateDewPoint(temp: temperature, relativeHumidity: humidity)
											.formatted(.number.precision(.fractionLength(0))) + "°"
										HumidityCompactWidget(humidity: Int(humidity), dewPoint: dewPoint)
									} else {
										HumidityCompactWidget(humidity: Int(humidity), dewPoint: nil)
									}
								}
								if let pressure = metrics.barometricPressure {
									PressureCompactWidget(pressure: pressure.formatted(.number.precision(.fractionLength(2))), unit: "hPA", low: pressure <= 1009.144)
								}
								if let windSpeed = metrics.windSpeed {
									let windSpeedMeasurement = Measurement(value: Double(windSpeed), unit: UnitSpeed.metersPerSecond)
									let windGust = metrics.windGust.map { Measurement(value: Double($0), unit: UnitSpeed.metersPerSecond) }
									let direction = cardinalValue(from: Double(metrics.windDirection ?? 0))
									WindCompactWidget(speed: windSpeedMeasurement.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))),
													  gust: metrics.windGust ?? 0.0 > 0.0 ? windGust?.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))) : "", direction: direction)
								}
								if let rainfall1h = metrics.rainfall1H {
									let locale = NSLocale.current as NSLocale
									let usesMetricSystem = locale.usesMetricSystem
									let unit = usesMetricSystem ? UnitLength.millimeters : UnitLength.inches
									let unitLabel = usesMetricSystem ? "mm" : "in"
									let measurement = Measurement(value: Double(rainfall1h), unit: UnitLength.millimeters)
									let decimals = usesMetricSystem ? 0 : 1
									let formattedRain = measurement.converted(to: unit).value.formatted(.number.precision(.fractionLength(decimals)))
									RainfallCompactWidget(timespan: .rainfall1H, rainfall: formattedRain, unit: unitLabel)
								}
								if let rainfall24h = metrics.rainfall24H {
									let locale = NSLocale.current as NSLocale
									let usesMetricSystem = locale.usesMetricSystem
									let unit = usesMetricSystem ? UnitLength.millimeters : UnitLength.inches
									let unitLabel = usesMetricSystem ? "mm" : "in"
									let measurement = Measurement(value: Double(rainfall24h), unit: UnitLength.millimeters)
									let decimals = usesMetricSystem ? 0 : 1
									let formattedRain = measurement.converted(to: unit).value.formatted(.number.precision(.fractionLength(decimals)))
									RainfallCompactWidget(timespan: .rainfall24H, rainfall: formattedRain, unit: unitLabel)
								}
								if let radiation = metrics.radiation {
									RadiationCompactWidget(radiation: radiation.formatted(.number.precision(.fractionLength(1))), unit: "µR/hr")
								}
								if let weight = metrics.weight {
									let weightMeasurement = Measurement(value: Double(weight), unit: UnitMass.kilograms)
									let usesMetric = Locale.current.measurementSystem == .metric
									let weightUnit = usesMetric ? UnitMass.kilograms : UnitMass.pounds
									let weightLabel = usesMetric ? "kg" : "lbs"
									WeightCompactWidget(weight: weightMeasurement.converted(to: weightUnit).value.formatted(.number.precision(.fractionLength(1))), unit: weightLabel)
								}
								if let distance = metrics.distance {
									let distMeasurement = Measurement(value: Double(distance), unit: UnitLength.millimeters)
									let usesMetric = Locale.current.measurementSystem == .metric
									let distUnit = usesMetric ? UnitLength.millimeters : UnitLength.inches
									let distLabel = usesMetric ? "mm" : "in"
									let distDecimals = usesMetric ? 0 : 1
									DistanceCompactWidget(distance: distMeasurement.converted(to: distUnit).value.formatted(.number.precision(.fractionLength(distDecimals))), unit: distLabel)
								}
								if let soilTemperature = metrics.soilTemperature {
									let locale = NSLocale.current as NSLocale
									let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
									let unit = (localeUnit as? String) == "Fahrenheit" ? "°F" : "°C"
									SoilTemperatureCompactWidget(temperature: soilTemperature.localeTemperature().formatted(.number.precision(.fractionLength(0))), unit: unit)
								}
								if let soilMoisture = metrics.soilMoisture {
									SoilMoistureCompactWidget(moisture: soilMoisture.formatted(.number.precision(.fractionLength(0))), unit: "%")
								}
							}
							.padding(metrics.iaq ?? -1 > 0 ? .bottom : .vertical)
						}
					}
				}
				.accessibilityElement(children: .combine)
			}
		}
	}

	// MARK: - Air Quality Section

	@ViewBuilder
	private var airQualitySection: some View {
		if let metrics = latestAirQualityMetrics,
		   metrics.pm25Standard != nil || metrics.pm10Standard != nil || metrics.pm100Standard != nil {
			Section("Air Quality") {
				VStack {
					// design#54: once ~12h of PM2.5 history exists, headline the NowCast-derived EPA AQI
					// gauge above the raw particulate-matter readings (µg/m³). Without enough history the
					// gauge is omitted and only the raw readings show — never a misleading instantaneous AQI.
					if let aqi = airQualityNowCastAQI {
						AirQualityIndex(aqi: aqi, displayMode: .gradient)
							.padding(.vertical)
					}
					LazyVGrid(columns: gridItemLayout) {
						if let pm25 = metrics.pm25Standard {
							ParticulateMatterCompactWidget(label: "PM2.5", value: pm25)
						}
						if let pm10 = metrics.pm10Standard {
							ParticulateMatterCompactWidget(label: "PM1.0", value: pm10)
						}
						if let pm100 = metrics.pm100Standard {
							ParticulateMatterCompactWidget(label: "PM10", value: pm100)
						}
					}
					.padding(.bottom)
				}
			}
			.accessibilityElement(children: .combine)
		}
	}

	// MARK: - Power Section

	@ViewBuilder
	private var powerSection: some View {
		if let powerMetrics = latestPowerMetrics {
			Section("Power") {
				VStack {
					PowerMetrics(metric: powerMetrics)
				}
				.accessibilityElement(children: .combine)
			}
		}
	}

	// MARK: - Logs Section

	@ViewBuilder
	private var logsSection: some View {
		let hasDeviceMetrics = logAvailability.hasDeviceMetrics
		let hasPositions = logAvailability.hasPositions
		let hasEnvironmentMetrics = logAvailability.hasEnvironmentMetrics
		let hasAirQualityMetrics = logAvailability.hasAirQualityMetrics
		let hasTraceRoutes = logAvailability.hasTraceRoutes
		let hasPowerMetrics = logAvailability.hasPowerMetrics
		let hasDetectionSensorMetrics = logAvailability.hasDetectionSensorMetrics
		let hasPax = logAvailability.hasPax

		Section("Logs") {
			NavigationLink {
				DeviceMetricsLog(node: node)
			} label: {
				Label {
					Text("Device Metrics Log")
				} icon: {
					Image(systemName: "flipphone")
						.symbolRenderingMode(.multicolor)
				}
			}
			.disabled(!hasDeviceMetrics)
			if showMapLink {
				NavigationLink {
					NodeMapSwiftUI(node: node, showUserLocation: accessoryManager.activeDeviceNum == nodeNum)
				} label: {
					Label {
						Text("Node Map")
					} icon: {
						Image(systemName: "map")
							.symbolRenderingMode(.multicolor)
					}
				}
				.disabled(!hasPositions)
				if hasPositions {
					Button {
						router.selectedTab = .map
						router.mapState = .coverageEstimate(nodeNum)
					} label: {
						Label {
							Text("Estimate Coverage")
						} icon: {
							Image("custom.radio.tower")
						}
					}
				}
			}
			NavigationLink {
				PositionLog(node: node)
			} label: {
				Label {
					Text("Position Log")
				} icon: {
					Image(systemName: "mappin.and.ellipse")
						.symbolRenderingMode(.multicolor)
				}
			}
			.disabled(!hasPositions)
			NavigationLink {
				EnvironmentMetricsLog(node: node)
			} label: {
				Label {
					Text("Environment Metrics Log")
				} icon: {
					Image(systemName: "cloud.sun.rain")
						.symbolRenderingMode(.multicolor)
				}
			}
			.disabled(!hasEnvironmentMetrics)
			NavigationLink {
				AirQualityMetricsLog(node: node)
			} label: {
				Label {
					Text("Air Quality Metrics Log")
				} icon: {
					Image(systemName: "aqi.medium")
						.symbolRenderingMode(.multicolor)
				}
			}
			.disabled(!hasAirQualityMetrics)
			NavigationLink {
				TraceRouteLog(node: node)
			} label: {
				Label {
					Text("Trace Route Log")
				} icon: {
					Image(systemName: "signpost.right.and.left")
						.symbolRenderingMode(.multicolor)
				}
			}
			.disabled(!hasTraceRoutes)
			NavigationLink {
				PowerMetricsLog(node: node)
			} label: {
				Label {
					Text("Power Metrics Log")
				} icon: {
					Image(systemName: "bolt")
						.symbolRenderingMode(.multicolor)
				}
			}
			.disabled(!hasPowerMetrics)
			NavigationLink {
				DetectionSensorLog(node: node)
			} label: {
				Label {
					Text("Detection Sensor Log")
				} icon: {
					Image(systemName: "sensor")
						.symbolRenderingMode(.multicolor)
				}
			}
			.disabled(!hasDetectionSensorMetrics)
			NavigationLink {
				LocalStatsLog(node: node)
			} label: {
				Label {
					Text("Local Stats Log")
				} icon: {
					Image(systemName: "chart.bar")
						.symbolRenderingMode(.multicolor)
				}
			}
			.disabled(!node.hasLocalStats)
			if hasPax {
				NavigationLink {
					PaxCounterLog(node: node)
				} label: {
					Label {
						Text("paxcounter.log")
					} icon: {
						Image(systemName: "figure.walk.motion")
							.symbolRenderingMode(.multicolor)
					}
				}
				.disabled(!hasPax)
			}
		}
	}

	// MARK: - Actions Section

	@ViewBuilder
	private var actionsSection: some View {
		Section("Actions") {
			if let user = currentUser {
				NodeAlertsButton(
					context: context,
					node: node,
					user: user
				)
				if ShareContactQR.canShareContact(for: shareContactNode) {
					Button {
						showingShareContactQR = true
					} label: {
						Label("Share Contact QR", systemImage: "qrcode")
					}
				}
			}
			if let connectedNode {
				FavoriteNodeButton(
					node: node
				)
				if accessoryManager.activeDeviceNum != nodeNum {
					if !(currentUser?.unmessagable ?? true) {
						Button(action: {
							if let url = URL(string: "meshtastic:///messages?userNum=\(nodeNum)") {
								UIApplication.shared.open(url)
							}
						}) {
							Label("Message", systemImage: "message")
						}
					}
					ExchangePositionsButton(
						node: node,
						connectedNode: connectedNode
					)
					RequestLocalStatsButton(node: node)
					ExchangeUserInfoButton(
						node: node,
						connectedNode: connectedNode
					)
					TraceRouteButton(
						node: node
					)
					if node.isStoreForwardRouter {
						ClientHistoryButton(
							connectedNode: connectedNode,
							node: node
						)
					}
					// Liveness screen: `latestPosition` is a @State handle refreshed on a cadence;
					// if ingestion deleted the row since the last refresh, reading a persisted
					// property on it traps in SwiftData. Skip rendering until the next refresh.
					if let latestPosition, latestPosition.modelContext != nil, !latestPosition.isDeleted {
					#if !targetEnvironment(macCatalyst)
						if latestPosition.isPreciseLocation {
							Button {
								showingCompassSheet = true
							} label: {
								Label {
									Text("Open Compass")
								} icon: {
									Image(systemName: "safari")
								}
							}
						}
					#endif
						NavigateToButton(node: node)
					}
					#if !targetEnvironment(macCatalyst)
					if WatchSessionManager.shared.isWatchAvailable {
						Button {
							WatchSessionManager.shared.sendNodeForFoxhunt(nodeNum)
						} label: {
							Label {
								Text("Foxhunt on your watch")
							} icon: {
								Image("custom.foxhunt")
							}
						}
					}
					#endif
					IgnoreNodeButton(
						node: node
					)
					DeleteNodeButton(
						connectedNode: connectedNode,
						node: node
					)
				}
			}
		}
	}

	// MARK: - Administration Section

	@ViewBuilder
	private var administrationSection: some View {
		if connectedNode != nil, accessoryManager.isConnected {
			Section("Administration") {
				let administrationUserPair = self.administrationUserPair
				if nodeNum != accessoryManager.activeDeviceNum {
					remoteAdminEntry(administrationUserPair: administrationUserPair)
				}
				if let metadata = node.metadata {
				if UserDefaults.enableAdministration {
					Button {
						Task {
							guard let administrationUserPair else { return }
							do {
								_ = try await accessoryManager.requestDeviceMetadata(
									fromUser: administrationUserPair.fromUser,
									toUser: administrationUserPair.toUser
								)
								Logger.mesh.info("Sent node metadata request from node details")
							} catch {
								Logger.mesh.error("Failed to send node metadata request from node details")
							}
						}
					} label: {
						Label {
							Text("Refresh device metadata")
						} icon: {
							Image(systemName: "arrow.clockwise")
						}
					}
					.disabled(administrationUserPair == nil)
				}
				if metadata.canShutdown {
					Button {
						showingShutdownConfirm = true
					} label: {
						Label("Power Off", systemImage: "power")
					}.confirmationDialog(
						"Are you sure?",
						isPresented: $showingShutdownConfirm
					) {
						Button("Shutdown Node?", role: .destructive) {
							Task {
								guard let administrationUserPair else { return }
								do {
									try await accessoryManager.sendShutdown(
										fromUser: administrationUserPair.fromUser,
										toUser: administrationUserPair.toUser
									)
								} catch {
									Logger.mesh.warning("Shutdown Failed")
								}
							}
						}
					}
					.disabled(administrationUserPair == nil)
				}
				Button {
					showingRebootConfirm = true
				} label: {
					Label(
						"Reboot",
						systemImage: "arrow.triangle.2.circlepath"
					)
				}.confirmationDialog(
					"Are you sure?",
					isPresented: $showingRebootConfirm
				) {
						Button("Reboot node?", role: .destructive) {
							Task {
							guard let administrationUserPair else { return }
							do {
								try await accessoryManager.sendReboot(
									fromUser: administrationUserPair.fromUser,
									toUser: administrationUserPair.toUser
								)
							} catch {
								Logger.mesh.warning("Reboot Failed")
							}
						}
					}
				}
				.disabled(administrationUserPair == nil)
				Button {
					pendingAdminTarget = currentAdminTarget
					showingSetTimeConfirm = true
				} label: {
					Label("Set Time", systemImage: "clock")
				}
				.confirmationDialog(
					"Set time on \(pendingAdminTarget?.name ?? "node")?",
					isPresented: $showingSetTimeConfirm,
					titleVisibility: .visible
				) {
					Button("Set time to now") {
						Task {
							guard let target = pendingAdminTarget else { return }
							isPerformingAdminAction = true
							defer { isPerformingAdminAction = false }
							let error = await RemoteAdminActionGuard.run(
								target: target,
								activeRadioNum: { accessoryManager.activeDeviceNum },
								activeConnectionID: { accessoryManager.activeConnection.map { ObjectIdentifier($0.connection) } },
								isConnected: { accessoryManager.isConnected },
								hasLiveSession: { getNodeInfo(id: target.nodeNum, context: context)?.hasLiveAdminSession == true }
							) {
								guard let pair = administrationUserPair, pair.toUser.num == target.nodeNum else { throw AccessoryError.connectionFailed("The selected target is no longer available") }
								try await accessoryManager.sendTime(fromUser: pair.fromUser, toUser: pair.toUser)
							}
							if let error { adminErrorMessage = "Set Time failed for \(target.name): \(error)" }
						}
					}
				}
				.disabled(administrationUserPair == nil || nodeNum == accessoryManager.activeDeviceNum || isPerformingAdminAction)
				Button {
					pendingAdminTarget = currentAdminTarget
					showingFactoryResetConfirm = true
				} label: {
					Label("Factory Reset", systemImage: "arrowcounterclockwise")
				}
				.confirmationDialog(
					"Factory reset \(pendingAdminTarget?.name ?? "node")?",
					isPresented: $showingFactoryResetConfirm,
					titleVisibility: .visible
				) {
					Button("Delete all config?", role: .destructive) {
						Task {
							guard let target = pendingAdminTarget else { return }
							isPerformingAdminAction = true
							defer { isPerformingAdminAction = false }
							let result = await RemoteAdminActionGuard.runOutcome(
								target: target,
								activeRadioNum: { accessoryManager.activeDeviceNum },
								activeConnectionID: { accessoryManager.activeConnection.map { ObjectIdentifier($0.connection) } },
								isConnected: { accessoryManager.isConnected },
								hasLiveSession: { getNodeInfo(id: target.nodeNum, context: context)?.hasLiveAdminSession == true }
							) {
								guard let pair = administrationUserPair, pair.toUser.num == target.nodeNum else { throw AccessoryError.connectionFailed("The selected target is no longer available") }
								return try await accessoryManager.sendFactoryReset(fromUser: pair.fromUser, toUser: pair.toUser)
							}
							switch result {
							case .acknowledged: adminErrorMessage = "Factory Reset acknowledged for \(target.name)."
							case .verified: adminErrorMessage = "Factory Reset verified for \(target.name)."
							case .unconfirmed: adminErrorMessage = "Factory Reset unconfirmed for \(target.name). Check the target before retrying."
							case .failed(let error): adminErrorMessage = "Factory Reset failed for \(target.name): \(error)"
							}
						}
					}
					Button("Delete all config, keys and BLE bonds?", role: .destructive) {
						Task {
							guard let target = pendingAdminTarget else { return }
							isPerformingAdminAction = true
							defer { isPerformingAdminAction = false }
							let result = await RemoteAdminActionGuard.runOutcome(
								target: target,
								activeRadioNum: { accessoryManager.activeDeviceNum },
								activeConnectionID: { accessoryManager.activeConnection.map { ObjectIdentifier($0.connection) } },
								isConnected: { accessoryManager.isConnected },
								hasLiveSession: { getNodeInfo(id: target.nodeNum, context: context)?.hasLiveAdminSession == true }
							) {
								guard let pair = administrationUserPair, pair.toUser.num == target.nodeNum else { throw AccessoryError.connectionFailed("The selected target is no longer available") }
								return try await accessoryManager.sendFactoryReset(fromUser: pair.fromUser, toUser: pair.toUser, resetDevice: true)
							}
							switch result {
							case .acknowledged: adminErrorMessage = "Factory Reset acknowledged for \(target.name)."
							case .verified: adminErrorMessage = "Factory Reset verified for \(target.name)."
							case .unconfirmed: adminErrorMessage = "Factory Reset unconfirmed for \(target.name). Check the target before retrying."
							case .failed(let error): adminErrorMessage = "Factory Reset failed for \(target.name): \(error)"
							}
						}
					}
				}
				.disabled(administrationUserPair == nil || nodeNum == accessoryManager.activeDeviceNum || isPerformingAdminAction)
				Button {
					pendingAdminTarget = currentAdminTarget
					showingNodeDBResetConfirm = true
				} label: {
					Label("NodeDB Reset", systemImage: "list.bullet.rectangle")
				}
				.confirmationDialog(
					"Reset node database on \(pendingAdminTarget?.name ?? "node")?",
					isPresented: $showingNodeDBResetConfirm,
					titleVisibility: .visible
				) {
					Button("Reset node database, preserving favorites") {
						Task {
							guard let target = pendingAdminTarget else { return }
							isPerformingAdminAction = true
							defer { isPerformingAdminAction = false }
							let result = await RemoteAdminActionGuard.runOutcome(
								target: target,
								activeRadioNum: { accessoryManager.activeDeviceNum },
								activeConnectionID: { accessoryManager.activeConnection.map { ObjectIdentifier($0.connection) } },
								isConnected: { accessoryManager.isConnected },
								hasLiveSession: { getNodeInfo(id: target.nodeNum, context: context)?.hasLiveAdminSession == true }
							) {
								guard let pair = administrationUserPair, pair.toUser.num == target.nodeNum else { throw AccessoryError.connectionFailed("The selected target is no longer available") }
								return try await accessoryManager.sendNodeDBReset(fromUser: pair.fromUser, toUser: pair.toUser, preserveFavorites: true)
							}
							switch result {
							case .acknowledged: adminErrorMessage = "NodeDB Reset acknowledged for \(target.name)."
							case .verified: adminErrorMessage = "NodeDB Reset verified for \(target.name)."
							case .unconfirmed: adminErrorMessage = "NodeDB Reset unconfirmed for \(target.name). Check the target before retrying."
							case .failed(let error): adminErrorMessage = "NodeDB Reset failed for \(target.name): \(error)"
							}
						}
					}
					Button("Reset node database and favorites?", role: .destructive) {
						Task {
							guard let target = pendingAdminTarget else { return }
							isPerformingAdminAction = true
							defer { isPerformingAdminAction = false }
							let result = await RemoteAdminActionGuard.runOutcome(
								target: target,
								activeRadioNum: { accessoryManager.activeDeviceNum },
								activeConnectionID: { accessoryManager.activeConnection.map { ObjectIdentifier($0.connection) } },
								isConnected: { accessoryManager.isConnected },
								hasLiveSession: { getNodeInfo(id: target.nodeNum, context: context)?.hasLiveAdminSession == true }
							) {
								guard let pair = administrationUserPair, pair.toUser.num == target.nodeNum else { throw AccessoryError.connectionFailed("The selected target is no longer available") }
								return try await accessoryManager.sendNodeDBReset(fromUser: pair.fromUser, toUser: pair.toUser, preserveFavorites: false)
							}
							switch result {
							case .acknowledged: adminErrorMessage = "NodeDB Reset acknowledged for \(target.name)."
							case .verified: adminErrorMessage = "NodeDB Reset verified for \(target.name)."
							case .unconfirmed: adminErrorMessage = "NodeDB Reset unconfirmed for \(target.name). Check the target before retrying."
							case .failed(let error): adminErrorMessage = "NodeDB Reset failed for \(target.name): \(error)"
							}
						}
					}
				}
				.disabled(administrationUserPair == nil || nodeNum == accessoryManager.activeDeviceNum || isPerformingAdminAction)
				if isPerformingAdminAction {
					HStack {
						ProgressView()
						Text("Waiting for target acknowledgement…")
							.foregroundColor(.secondary)
							.font(.caption)
					}
				}
				}
			}
			.alert("Admin Action Result", isPresented: Binding(
				get: { adminErrorMessage != nil },
				set: { if !$0 { adminErrorMessage = nil } }
			)) {
				Button("OK", role: .cancel) { adminErrorMessage = nil }
			} message: {
				Text(adminErrorMessage ?? "")
			}
		}
	}

	@ViewBuilder
	private func remoteAdminEntry(administrationUserPair: (fromUser: UserEntity, toUser: UserEntity)?) -> some View {
		let targetName = currentUser?.displayLongName ?? "Unknown".localized
		switch remoteAdminState {
		case .establishing:
			HStack {
				ProgressView()
				Text("Establishing remote admin for \(targetName)")
			}
		case .active:
			Button {
				remoteAdminState = .establishing
				remoteAdminAttemptID = UUID()
			} label: {
				Label("Remote Admin: \(targetName)", systemImage: "checkmark.shield")
					.frame(minWidth: 48, minHeight: 48, alignment: .leading)
			}
		case .failed(let result):
			VStack(alignment: .leading) {
				Button {
					remoteAdminState = .establishing
					remoteAdminAttemptID = UUID()
				} label: {
					Label("Retry Remote Admin for \(targetName)", systemImage: "arrow.clockwise")
						.frame(minWidth: 48, minHeight: 48, alignment: .leading)
				}
				Text("Remote admin failed: \(RemoteAdminSessionWaiter.description(for: result)).")
					.font(.caption)
					.foregroundStyle(.orange)
			}
			.disabled(administrationUserPair == nil || !UserDefaults.enableAdministration)
		case .stale:
			VStack(alignment: .leading) {
				Button {
					remoteAdminState = .establishing
					remoteAdminAttemptID = UUID()
				} label: {
					Label("Remote Admin: \(targetName)", systemImage: "shield")
						.frame(minWidth: 48, minHeight: 48, alignment: .leading)
				}
				if !UserDefaults.enableAdministration {
					Text("Enable Administration in App Settings to use remote admin.")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			}
			.disabled(administrationUserPair == nil || !UserDefaults.enableAdministration)
		}
	}

	@MainActor
	private func establishRemoteAdminSession() async {
		guard let attemptID = remoteAdminAttemptID,
			let radioNum = accessoryManager.activeDeviceNum,
			let connection = accessoryManager.activeConnection?.connection,
			nodeNum != radioNum else {
			remoteAdminState = .failed(.targetChanged)
			return
		}
		defer {
			if remoteAdminAttemptID == attemptID { remoteAdminAttemptID = nil }
		}
		guard UserDefaults.enableAdministration else {
			remoteAdminState = .failed(.requestFailed)
			return
		}
		guard let administrationUserPair else {
			remoteAdminState = .failed(.disconnected)
			return
		}
		let connectionID = ObjectIdentifier(connection)
		let result = await RemoteAdminSessionOrchestrator.establish(
			allowed: { UserDefaults.enableAdministration && accessoryManager.isConnected },
			attemptIsCurrent: { [weak accessoryManager, weak node, weak router] in
				accessoryManager?.activeDeviceNum == radioNum
					&& accessoryManager?.activeConnection.map { ObjectIdentifier($0.connection) } == connectionID
					&& node?.modelContext != nil && node?.isDeleted == false
					&& (router?.selectedNodeNum == nil || router?.selectedNodeNum == nodeNum)
					&& self.remoteAdminAttemptID == attemptID
			},
			// Fetch to refresh the retained main-context node after the packet actor saves a session.
			fresh: { getNodeInfo(id: nodeNum, context: context)?.hasLiveAdminSession == true },
			request: {
				_ = try await accessoryManager.requestDeviceMetadata(
					fromUser: administrationUserPair.fromUser,
					toUser: administrationUserPair.toUser
				)
			},
			wait: {
				await RemoteAdminSessionWaiter.wait(
					isLive: { getNodeInfo(id: nodeNum, context: context)?.hasLiveAdminSession == true },
					isConnected: { [weak accessoryManager] in
						accessoryManager?.isConnected == true
						&& accessoryManager?.activeDeviceNum == radioNum
						&& accessoryManager?.activeConnection.map { ObjectIdentifier($0.connection) } == connectionID
						&& self.remoteAdminAttemptID == attemptID
					},
					targetIsCurrent: { [weak node, weak router] in
						node?.modelContext != nil && node?.isDeleted == false
						&& (router?.selectedNodeNum == nil || router?.selectedNodeNum == nodeNum)
					}
				)
			}
		)
		guard result == .active else {
			remoteAdminState = .failed(result)
			return
		}
		guard UserDefaults.enableAdministration,
			accessoryManager.isConnected,
			accessoryManager.activeDeviceNum == radioNum,
			accessoryManager.activeConnection.map({ ObjectIdentifier($0.connection) }) == connectionID,
			node.modelContext != nil, !node.isDeleted,
			remoteAdminAttemptID == attemptID else {
			remoteAdminState = .failed(.targetChanged)
			return
		}
		remoteAdminState = .active
		remoteSettingsDestination = RemoteAdminSettingsDestination(nodeNum: nodeNum, radioNum: radioNum, connectionID: connectionID)
	}

	private func refreshNodeSummary() {
		let deviceMetrics = node.latestDeviceMetrics
		let environmentMetrics = node.latestEnvironmentMetrics
		let airQualityMetrics = node.latestAirQualityMetrics
		let airQualityAQI = node.airQualityNowCastAQI
		let powerMetrics = node.latestPowerMetrics
		let position = node.latestPosition
		latestDeviceMetrics = deviceMetrics
		latestEnvironmentMetrics = environmentMetrics
		latestAirQualityMetrics = airQualityMetrics
		airQualityNowCastAQI = airQualityAQI
		latestPowerMetrics = powerMetrics
		latestPosition = position
		logAvailability = NodeDetailLogAvailability(
			hasDeviceMetrics: deviceMetrics != nil,
			hasPositions: position != nil,
			hasEnvironmentMetrics: environmentMetrics != nil,
			hasAirQualityMetrics: airQualityMetrics != nil,
			hasTraceRoutes: node.hasTraceRoutes,
			hasPowerMetrics: powerMetrics != nil,
			hasDetectionSensorMetrics: node.hasDetectionSensorMetrics,
			hasPax: node.hasPax
		)
	}

	private func hasDataForLatestEnvironmentMetrics(attributes: [String]) -> Bool {
		guard let latest = latestEnvironmentMetrics else { return false }
		let mirror = Mirror(reflecting: latest)
		for attribute in attributes {
			if let child = mirror.children.first(where: { $0.label == attribute }) {
				let childMirror = Mirror(reflecting: child.value)
				if childMirror.displayStyle == .optional {
					if childMirror.children.count > 0 { return true }
				} else {
					return true
				}
			}
		}
		return false
	}
}

func cardinalValue(from heading: Double) -> String {
	switch heading {
	case 0 ..< 22.5:
		return "North"
	case 22.5 ..< 67.5:
		return "North East"
	case 67.5 ..< 112.5:
		return "East"
	case 112.5 ..< 157.5:
		return "South East"
	case 157.5 ..< 202.5:
		return "South"
	case 202.5 ..< 247.5:
		return "South West"
	case 247.5 ..< 292.5:
		return "West"
	case 292.5 ..< 337.5:
		return "North West"
	case 337.5 ... 360.0:
		return "North"
	default:
		return ""
	}
}

func abbreviatedCardinalValue(from heading: Double) -> String {
	switch heading {
	case 0 ..< 22.5:
		return "N"
	case 22.5 ..< 67.5:
		return "NE"
	case 67.5 ..< 112.5:
		return "E"
	case 112.5 ..< 157.5:
		return "E"
	case 157.5 ..< 202.5:
		return "S"
	case 202.5 ..< 247.5:
		return "SW"
	case 247.5 ..< 292.5:
		return "W"
	case 292.5 ..< 337.5:
		return "NW"
	case 337.5 ... 360.0:
		return "N"
	default:
		return ""
	}
}
