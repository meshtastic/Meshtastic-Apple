/*
 Abstract:
 A view showing the details for a node.
 */

import SwiftUI
import WeatherKit
import MapKit
import CoreLocation
import OSLog

struct NodeDetail: View {
	private let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	private static let relativeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter
	}()
	var modemPreset: ModemPresets = ModemPresets(
		rawValue: UserDefaults.modemPreset
	) ?? ModemPresets.longFast

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var showingShutdownConfirm: Bool = false
	@State private var showingRebootConfirm: Bool = false
	@State private var dateFormatRelative: Bool = true

	// The node the device is currently connected to
	var connectedNode: NodeInfoEntity?

	// The node information being displayed on the detail screen
	@ObservedObject
	var node: NodeInfoEntity

	var columnVisibility = NavigationSplitViewVisibility.all

	var body: some View {
		NavigationStack {
			List {
				let connectedNode = getNodeInfo(
					id: bleManager.connectedPeripheral?.num ?? -1,
					context: context
				)

				Section("Hardware") {
					NodeInfoItem(node: node)
				}
				.accessibilityElement(children: .combine)
				Section("Node") { // Node
					HStack(alignment: .center) {
						Spacer()
						CircleText(
							text: node.user?.shortName ?? "?",
							color: Color(UIColor(hex: UInt32(node.num))),
							circleSize: 75
						)
						if node.snr != 0 && !node.viaMqtt && node.hopsAway == 0 {
							Spacer()
							VStack {
								let signalStrength = getLoRaSignalStrength(snr: node.snr, rssi: node.rssi, preset: modemPreset)
								LoRaSignalStrengthIndicator(signalStrength: signalStrength)
								Text("Signal \(signalStrength.description)").font(.footnote)
								Text("SNR \(String(format: "%.2f", node.snr))dB")
									.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
									.font(.caption)
								Text("RSSI \(node.rssi)dB")
									.foregroundColor(getRssiColor(rssi: node.rssi))
									.font(.caption)
							}
							.accessibilityElement(children: .combine)
						}
						if node.telemetries?.count ?? 0 > 0 {
							Spacer()
							BatteryGauge(node: node)
						}
						Spacer()
					}
					.accessibilityElement(children: .combine)
					.listRowSeparator(.hidden)
					if let user = node.user {
						if !user.keyMatch {
							Label {
								VStack(alignment: .leading) {
									Text("Public Key Mismatch")
										.font(.title3)
										.foregroundStyle(.red)
									Text("The most recent public key for this node does not match the previously recorded key. You can delete the node and let it exchange keys again, but this also may indicate a more serious security problem. Contact the user through another trusted channel to determine if the key change was due to a factory reset or other intentional action.")
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
					HStack {
						Label {
							Text("Node Number")
						} icon: {
							Image(systemName: "number")
								.symbolRenderingMode(.hierarchical)
						}
						Spacer()
						Text(String(node.num))
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
						Text(node.num.toHex())
						.textSelection(.enabled)
					}
					.accessibilityElement(children: .combine)

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

					if let role = node.user?.role, let deviceRole = DeviceRoles(rawValue: Int(role)) {
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

					if let dm = node.telemetries?.filtered(using: NSPredicate(format: "metricsType == 0")).lastObject as? TelemetryEntity, let uptimeSeconds = dm.uptimeSeconds {
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
					}
				}

				// Note, as you add widgets, you should add to the `hasDataForLatestPositions` array
				// This will make sure the "Environment" section is only displayed when the node has a position
				// to use with WeatherKit, or has actual data in the most recent EnvironmentMetrics entity
				// that will be rendered in this section.
				if node.hasPositions && UserDefaults.environmentEnableWeatherKit
					|| node.hasDataForLatestEnvironmentMetrics(attributes: ["iaq", "temperature", "relativeHumidity", "barometricPressure", "windSpeed", "radiation", "weight", "Distance", "soilTemperature", "soilMoisture"]) {
					Section("Environment") {
						// Group weather/environment data for better VoiceOver experience
						VStack {
							if !node.hasEnvironmentMetrics {
								LocalWeatherConditions(location: node.latestPosition?.nodeLocation)
							} else {
								VStack {
									if node.latestEnvironmentMetrics?.iaq ?? -1 > 0 {
										IndoorAirQuality(iaq: Int(node.latestEnvironmentMetrics?.iaq ?? 0), displayMode: .gradient)
											.padding(.vertical)
									}
									LazyVGrid(columns: gridItemLayout) {
										if let temperature = node.latestEnvironmentMetrics?.temperature?.shortFormattedTemperature() {
											WeatherConditionsCompactWidget(temperature: String(temperature), symbolName: "cloud.sun", description: "TEMP")
										}
										if let humidity = node.latestEnvironmentMetrics?.relativeHumidity {
											if let temperature = node.latestEnvironmentMetrics?.temperature {
												let dewPoint = calculateDewPoint(temp: temperature, relativeHumidity: humidity)
													.formatted(.number.precision(.fractionLength(0))) + "°"
												HumidityCompactWidget(humidity: Int(humidity), dewPoint: dewPoint)
											} else {
												HumidityCompactWidget(humidity: Int(humidity), dewPoint: nil)
											}
										}
										if let pressure = node.latestEnvironmentMetrics?.barometricPressure {
											PressureCompactWidget(pressure: pressure.formatted(.number.precision(.fractionLength(2))), unit: "hPA", low: pressure <= 1009.144)
										}
										if let windSpeed = node.latestEnvironmentMetrics?.windSpeed {
											let windSpeedMeasurement = Measurement(value: Double(windSpeed), unit: UnitSpeed.metersPerSecond)
											let windGust = node.latestEnvironmentMetrics?.windGust.map { Measurement(value: Double($0), unit: UnitSpeed.metersPerSecond) }
											let direction = cardinalValue(from: Double(node.latestEnvironmentMetrics?.windDirection ?? 0))
											WindCompactWidget(speed: windSpeedMeasurement.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))),
															gust: node.latestEnvironmentMetrics?.windGust ?? 0.0 > 0.0 ? windGust?.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))) : "", direction: direction)
										}
										if let rainfall1h = node.latestEnvironmentMetrics?.rainfall1H {
											let locale = NSLocale.current as NSLocale
											let usesMetricSystem = locale.usesMetricSystem // Returns true for metric (mm), false for imperial (inches)
											let unit = usesMetricSystem ? UnitLength.millimeters : UnitLength.inches
											let unitLabel = usesMetricSystem ? "mm" : "in"
											let measurement = Measurement(value: Double(rainfall1h), unit: UnitLength.millimeters)
											let decimals = usesMetricSystem ? 0 : 1
											let formattedRain = measurement.converted(to: unit).value.formatted(.number.precision(.fractionLength(decimals)))
											RainfallCompactWidget(timespan: .rainfall1H, rainfall: formattedRain, unit: unitLabel)
										}
										if let rainfall24h = node.latestEnvironmentMetrics?.rainfall24H {
											let locale = NSLocale.current as NSLocale
											let usesMetricSystem = locale.usesMetricSystem // Returns true for metric (mm), false for imperial (inches)
											let unit = usesMetricSystem ? UnitLength.millimeters : UnitLength.inches
											let unitLabel = usesMetricSystem ? "mm" : "in"
											let measurement = Measurement(value: Double(rainfall24h), unit: UnitLength.millimeters)
											let decimals = usesMetricSystem ? 0 : 1
											let formattedRain = measurement.converted(to: unit).value.formatted(.number.precision(.fractionLength(decimals)))
											RainfallCompactWidget(timespan: .rainfall24H, rainfall: formattedRain, unit: unitLabel)
										}
										if let radiation = node.latestEnvironmentMetrics?.radiation {
											RadiationCompactWidget(radiation: radiation.formatted(.number.precision(.fractionLength(1))), unit: "µR/hr")
										}
										if let weight = node.latestEnvironmentMetrics?.weight {
											WeightCompactWidget(weight: weight.formatted(.number.precision(.fractionLength(1))), unit: "kg")
										}
										if let distance = node.latestEnvironmentMetrics?.distance {
											DistanceCompactWidget(distance: distance.formatted(.number.precision(.fractionLength(0))), unit: "mm")
										}
										if let soilTemperature = node.latestEnvironmentMetrics?.soilTemperature {
											let locale = NSLocale.current as NSLocale
											let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
											let unit = localeUnit as? String ?? "Celsius" == "Fahrenheit" ? "°F" : "°C"
											SoilTemperatureCompactWidget(temperature: soilTemperature.localeTemperature().formatted(.number.precision(.fractionLength(0))), unit: unit)
										}
										if let soilMoisture = node.latestEnvironmentMetrics?.soilMoisture {
											SoilMoistureCompactWidget(moisture: soilMoisture.formatted(.number.precision(.fractionLength(0))), unit: "%")
										}
									}
									.padding(node.latestEnvironmentMetrics?.iaq ?? -1 > 0 ? .bottom : .vertical)
								}
							}
						}
						// Apply accessibility properties to the environment section
						.accessibilityElement(children: .combine)
					}
				}
				if node.hasPowerMetrics && node.latestPowerMetrics != nil {
					Section("Power") {
						VStack {
							if let metric = node.latestPowerMetrics {
								PowerMetrics(metric: metric)
							}
						}
						.accessibilityElement(children: .combine)
					}
				}
				Section("Logs") {
					// Metrics
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
					.disabled(!node.hasDeviceMetrics)

					NavigationLink {
						NodeMapSwiftUI(node: node, showUserLocation: connectedNode?.num ?? 0 == node.num)
					} label: {
						Label {
							Text("Node Map")
						} icon: {
							Image(systemName: "map")
								.symbolRenderingMode(.multicolor)
						}
					}
					.disabled(!node.hasPositions)

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
					.disabled(!node.hasPositions)

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
					.disabled(!node.hasEnvironmentMetrics)

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
					.disabled(node.traceRoutes?.count ?? 0 == 0)

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
					.disabled(!node.hasPowerMetrics)

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
					.disabled(!node.hasDetectionSensorMetrics)

					if node.hasPax {
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
						.disabled(!node.hasPax)
					}
				}

				Section("Actions") {
					if let user = node.user {
						NodeAlertsButton(
							context: context,
							node: node,
							user: user
						)
					}

					if let connectedNode {
						FavoriteNodeButton(
							bleManager: bleManager,
							context: context,
							node: node
						)
						if connectedNode.num != node.num {
							ExchangePositionsButton(
								bleManager: bleManager,
								node: node
							)
							TraceRouteButton(
								bleManager: bleManager,
								node: node
							)
							if node.isStoreForwardRouter {
								ClientHistoryButton(
									bleManager: bleManager,
									connectedNode: connectedNode,
									node: node
								)
							}
							if node.hasPositions {
								NavigateToButton(node: node)
								}
							IgnoreNodeButton(
								bleManager: bleManager,
								context: context,
								node: node
							)
							DeleteNodeButton(
								bleManager: bleManager,
								context: context,
								connectedNode: connectedNode,
								node: node
							)
						}
					}
				}

				if let metadata = node.metadata,
				   let connectedNode,
				   self.bleManager.connectedPeripheral != nil {
					Section("Administration") {
						if connectedNode.myInfo?.hasAdmin ?? false {
							Button {
								let adminMessageId = bleManager.requestDeviceMetadata(
									fromUser: connectedNode.user!,
									toUser: node.user!,
									adminIndex: connectedNode.myInfo!.adminIndex,
									context: context
								)
								if adminMessageId > 0 {
									Logger.mesh.info("Sent node metadata request from node details")
								}
							} label: {
								Label {
									Text("Refresh device metadata")
								} icon: {
									Image(systemName: "arrow.clockwise")
								}
							}
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
									if !bleManager.sendShutdown(
										fromUser: connectedNode.user!,
										toUser: node.user!,
										adminIndex: connectedNode.myInfo!.adminIndex
									) {
										Logger.mesh.warning("Shutdown Failed")
									}
								}
							}
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
								if !bleManager.sendReboot(
									fromUser: connectedNode.user!,
									toUser: node.user!,
									adminIndex: connectedNode.myInfo!.adminIndex
								) {
									Logger.mesh.warning("Reboot Failed")
								}
							}
						}
					}
				}
			}
			.listStyle(.insetGrouped)
			.navigationBarTitle(String(node.user?.longName?.addingVariationSelectors ?? "Unknown".localized), displayMode: .inline)
		}
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
