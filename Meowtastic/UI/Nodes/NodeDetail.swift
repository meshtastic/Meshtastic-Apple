import FirebaseAnalytics
import MapKit
import OSLog
import SwiftUI

struct NodeDetail: View {
	var isInSheet = false

	@ObservedObject
	var node: NodeInfoEntity

	private let distanceFormatter = MKDistanceFormatter()
	private let detailInfoFont = Font.system(size: 12, weight: .regular, design: .rounded)
	private let detailIconSize: CGFloat = 12

	@Environment(\.managedObjectContext)
	private var context
	@EnvironmentObject
	private var bleManager: BLEManager
	@EnvironmentObject
	private var nodeConfig: NodeConfig
	@EnvironmentObject
	private var locationManager: LocationManager

	@State
	private var showingShutdownConfirm = false
	@State
	private var showingRebootConfirm = false

	private var connectedNode: NodeInfoEntity? {
		getNodeInfo(
			id: bleManager.deviceConnected?.num ?? -1,
			context: context
		)
	}
	private var nodePosition: PositionEntity? {
		node.positions?.lastObject as? PositionEntity
	}
	private var nodePositionStale: Bool {
		nodePosition != nil
		&& nodePosition?.time?.isStale(threshold: AppConstants.nodeTelemetryThreshold) ?? true
		&& nodePosition?.speed ?? 0 > 0
	}
	private var nodeTelemetry: TelemetryEntity? {
		node
			.telemetries?
			.filtered(
				using: NSPredicate(format: "metricsType == 0")
			)
			.lastObject as? TelemetryEntity
	}
	private var nodeEnvironment: TelemetryEntity? {
		node
			.telemetries?
			.filtered(
				using: NSPredicate(format: "metricsType == 1")
			)
			.lastObject as? TelemetryEntity
	}
	private var nodeEnvironmentStale: Bool {
		nodeEnvironment != nil
		&& nodeEnvironment?.time?.isStale(threshold: AppConstants.nodeTelemetryThreshold) ?? true
	}

	var body: some View {
		NavigationStack {
			List {
				Section("Info") {
					hardwareInfo

					if nodePosition != nil {
						locationInfo
							.padding(.horizontal, 4)
					}

					if nodeEnvironment != nil {
						environmentInfo
							.padding(.horizontal, 4)
					}

					if nodePositionStale || nodeEnvironmentStale {
						HStack(alignment: .center, spacing: 8) {
							Image(systemName: "exclamationmark.triangle.fill")
								.font(detailInfoFont)
								.foregroundColor(.orange)
								.frame(width: detailIconSize)

							if nodePositionStale, nodeEnvironmentStale {
								Text("Position & environment data are stale")
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}
							else if nodePositionStale {
								Text("Position data are stale")
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}
							else if nodeEnvironmentStale {
								Text("Environment data are stale")
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}
						}
						.padding(.horizontal, 4)
					}
				}

				Section("Details") {
					nodeInfo
				}

				if !isInSheet {
					Section("Actions") {
						actions
					}

					if
						let connectedNode,
						let nodeMetadata = node.metadata,
						self.bleManager.deviceConnected != nil
					{
						Section("Administration") {
							admin(node: connectedNode, metadata: nodeMetadata)
						}
					}
				}
			}
			.listStyle(.insetGrouped)
		}
		.onAppear {
			Analytics.logEvent(
				AnalyticEvents.nodeDetail.id,
				parameters: AnalyticEvents.getParams(for: node, [ "sheet": isInSheet ])
			)
		}
	}

	@ViewBuilder
	private var hardwareInfo: some View {
		VStack {
			NodeInfoView(node: node)

			if node.hasPositions {
				if isInSheet {
					SimpleNodeMap(node: node)
						.frame(width: .infinity, height: 120)
						.cornerRadius(8)
						.padding(.top, 8)
						.disabled(true)
						.toolbar(.hidden)
				}
				else {
					NavigationLink {
						NavigationLazyView(
							NodeMap(node: node)
						)
					} label: {
						SimpleNodeMap(node: node)
							.frame(width: .infinity, height: 200)
							.cornerRadius(8)
							.padding(.top, 8)
							.disabled(true)
					}
				}
			}
		}
	}

	@ViewBuilder
	private var locationInfo: some View {
		if let position = nodePosition {
			HStack(alignment: .center, spacing: 8) {
				if
					let currentCoordinate = locationManager.lastKnownLocation?.coordinate,
					let lastCoordinate = (node.positions?.lastObject as? PositionEntity)?.coordinate
				{
					let myLocation = CLLocation(
						latitude: currentCoordinate.latitude,
						longitude: currentCoordinate.longitude
					)
					let location = CLLocation(
						latitude: lastCoordinate.latitude,
						longitude: lastCoordinate.longitude
					)
					let distance = location.distance(from: myLocation)
					let distanceFormatted = distanceFormatter.string(fromDistance: Double(distance))

					Image(systemName: "mappin.and.ellipse")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)

					Text(distanceFormatted)
						.font(detailInfoFont)
						.foregroundColor(.gray)

					Spacer()
						.frame(width: 4)
				}

				if position.speed > 0 {
					let speed = Measurement(
						value: Double(position.speed),
						unit: UnitSpeed.kilometersPerHour
					)
					let speedFormatted = speed.formatted(
						.measurement(
							width: .abbreviated,
							numberFormatStyle: .number.precision(.fractionLength(0))
						)
					)
					let heading = Angle.degrees(
						Double(position.heading)
					)
					let headingDegrees = Measurement(
						value: heading.degrees,
						unit: UnitAngle.degrees
					)
					let headingFormatted = headingDegrees.formatted(
						.measurement(
							width: .narrow,
							numberFormatStyle: .number.precision(.fractionLength(0))
						)
					)

					Image(systemName: "gauge.open.with.lines.needle.33percent")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)

					Text(speedFormatted)
						.font(detailInfoFont)
						.foregroundColor(.gray)

					Spacer()
						.frame(width: 4)

					Image(systemName: "safari")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)

					Text(headingFormatted)
						.font(detailInfoFont)
						.foregroundColor(.gray)

					Spacer()
						.frame(width: 4)
				}

				let altitudeFormatted = distanceFormatter.string(
					fromDistance: Double(position.altitude)
				)

				Image(systemName: "mountain.2")
					.font(detailInfoFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)

				Text(altitudeFormatted)
					.font(detailInfoFont)
					.foregroundColor(.gray)

				let precision = PositionPrecision(rawValue: Int(position.precisionBits))?.precisionMeters
				if let precision {
					let precisionFormatted = distanceFormatter.string(
						fromDistance: Double(precision)
					)

					Spacer()
						.frame(width: 4)

					Image(systemName: "scope")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)

					Text(precisionFormatted)
						.font(detailInfoFont)
						.foregroundColor(.gray)
				}

			}
		}
		else {
			EmptyView()
		}
	}

	@ViewBuilder
	private var environmentInfo: some View {
		if let nodeEnvironment {
			let temp = nodeEnvironment.temperature
			let tempFormatted = String(format: "%.1f", temp) + "°C"
			let humidityFormatted = String(format: "%.0f", nodeEnvironment.relativeHumidity.rounded()) + "%"
			let pressureFormatted = String(format: "%.0f", nodeEnvironment.barometricPressure.rounded()) + "hPa"
			let windFormatted = String(format: "%.0f", nodeEnvironment.windSpeed.rounded()) + "m/s"

			HStack(alignment: .center, spacing: 8) {
				if nodeEnvironment.windSpeed != 0 {
					Image(systemName: "arrow.up.circle")
						.rotationEffect(.degrees(Double(nodeEnvironment.windDirection)))
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)

					Text(windFormatted)
						.font(detailInfoFont)
						.foregroundColor(.gray)

					Spacer()
						.frame(width: 4)
				}

				if temp < 10 {
					Image(systemName: "thermometer.low")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
				else if temp < 25 {
					Image(systemName: "thermometer.medium")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
				else {
					Image(systemName: "thermometer.high")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}

				Text(tempFormatted)
					.font(detailInfoFont)
					.foregroundColor(.gray)

				if nodeEnvironment.relativeHumidity > 0, nodeEnvironment.relativeHumidity < 100 {
					Spacer()
						.frame(width: 4)

					Image(systemName: "humidity")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)

					Text(humidityFormatted)
						.font(detailInfoFont)
						.foregroundColor(.gray)
				}

				if nodeEnvironment.barometricPressure > 0 {
					Spacer()
						.frame(width: 4)

					Image(systemName: "barometer")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)

					Text(pressureFormatted)
						.font(detailInfoFont)
						.foregroundColor(.gray)
				}
			}
		}
		else {
			EmptyView()
		}
	}

	@ViewBuilder
	private var nodeInfo: some View {
		if let userID = node.user?.userId {
			HStack {
				Label {
					Text("User ID")
						.textSelection(.enabled)
				} icon: {
					Image(systemName: "person")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text(userID)
					.textSelection(.enabled)
			}
		}

		HStack {
			Label {
				Text("Node Number")
					.textSelection(.enabled)
			} icon: {
				Image(systemName: "number")
					.symbolRenderingMode(.monochrome)
					.foregroundColor(.accentColor)
			}

			Spacer()

			Text(String(node.num))
				.textSelection(.enabled)
		}

		if let role = node.user?.role, let deviceRole = DeviceRoles(rawValue: Int(role)) {
			HStack {
				Label {
					Text("Role")
				} icon: {
					Image(systemName: deviceRole.systemName)
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text(deviceRole.name)
			}
		}

		if let num = connectedNode?.num, num != node.num {
			HStack {
				Label {
					Text("Network")
				} icon: {
					if node.viaMqtt {
						Image(systemName: "network")
							.symbolRenderingMode(.monochrome)
							.foregroundColor(.accentColor)
					}
					else {
						Image(systemName: "antenna.radiowaves.left.and.right")
							.symbolRenderingMode(.monochrome)
							.foregroundColor(.accentColor)
					}
				}

				Spacer()

				if node.viaMqtt {
					Text("MQTT")
				}
				else {
					VStack(alignment: .trailing, spacing: 4) {
						Text("LoRa")

						if node.rssi != 0 || node.snr != 0 {
							HStack(spacing: 8) {
								if node.rssi != 0 {
									Text("RSSI: \(node.rssi)dBm")
										.font(.system(size: 10, weight: .light))
										.foregroundColor(.gray)
								}
								if node.snr != 0 {
									Text("SNR: \(String(format: "%.1f", node.snr))dB")
										.font(.system(size: 10, weight: .light))
										.foregroundColor(.gray)
								}
							}
						}
					}
				}
			}
		}

		if let channelUtil = nodeTelemetry?.channelUtilization {
			HStack {
				Label {
					Text("Channel")
				} icon: {
					Image(systemName: "arrow.left.arrow.right")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text(String(format: "%.2f", channelUtil) + "%")
			}
		}

		if let airUtil = nodeTelemetry?.airUtilTx {
			HStack {
				Label {
					Text("Air Time")
				} icon: {
					Image(systemName: "wave.3.right")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text(String(format: "%.2f", airUtil) + "%")
			}
		}

		HStack {
			Label {
				Text("Hops")
			} icon: {
				Image(systemName: node.hopsAway == 0 ? "eye" : "arrowshape.bounce.forward")
					.symbolRenderingMode(.monochrome)
					.foregroundColor(.accentColor)
			}

			Spacer()

			if node.hopsAway == 0 {
				Text("Direct visibility")
			}
			else if node.hopsAway == 1 {
				Text("\(node.hopsAway) hop")
			}
			else {
				Text("\(node.hopsAway) hops")
			}
		}

		if let num = connectedNode?.num, num != node.num {
			if
				let connectedPeripheral = bleManager.deviceConnected,
				node.num != connectedPeripheral.num
			{
				let routes = node.traceRoutes?.count ?? 0

				NavigationLink {
					NavigationLazyView(
						TraceRoute(node: node)
					)
				} label: {
					Label {
						Text("Trace Route")
					} icon: {
						if routes > 0 {
							Image(systemName: "signpost.right.and.left.fill")
								.symbolRenderingMode(.monochrome)
								.foregroundColor(.accentColor)
						}
						else {
							Image(systemName: "signpost.right.and.left")
								.symbolRenderingMode(.monochrome)
								.foregroundColor(.accentColor)
						}
					}
				}
			}
		}

		if
			let lastHeard = node.lastHeard,
			lastHeard.timeIntervalSince1970 > 0
		{
			HStack {
				Label {
					Text("Last Heard")
				} icon: {
					Image(systemName: "waveform.path.ecg")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text(lastHeard.relative())
					.textSelection(.enabled)
			}
		}

		if
			let firstHeard = node.firstHeard,
			firstHeard.timeIntervalSince1970 > 0
		{
			HStack {
				Label {
					Text("First Heard")
				} icon: {
					Image(systemName: "eye")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text(firstHeard.relative())
					.textSelection(.enabled)
			}
		}

		if let hwModel = node.user?.hwModel {
			HStack {
				Label {
					Text("Hardware")
				} icon: {
					Image(systemName: "flipphone")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text(hwModel)
			}
		}

		if let metadata = node.metadata, let firmwareVersion = metadata.firmwareVersion {
			HStack {
				Label {
					Text("Firmware")
				} icon: {
					Image(systemName: "memorychip")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text("v" + firmwareVersion)
			}
		}

		if let nodeTelemetry, nodeTelemetry.uptimeSeconds > 0 {
			let now = Date.now
			let later = now + TimeInterval(nodeTelemetry.uptimeSeconds)
			let uptimeFormatted = (now..<later).formatted(.components(style: .narrow))

			HStack {
				Label {
					Text("Uptime")
				} icon: {
					Image(systemName: "hourglass")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}

				Spacer()

				Text(uptimeFormatted)
					.textSelection(.enabled)
			}
		}
	}

	@ViewBuilder
	private var actions: some View {
		FavoriteNodeButton(
			bleManager: bleManager,
			nodeConfig: nodeConfig,
			context: context,
			node: node
		)

		if let user = node.user {
			NodeAlertsButton(
				context: context,
				node: node,
				user: user
			)
		}

		if
			let connectedDevice = bleManager.getConnectedDevice(),
			node.num != connectedDevice.num
		{
			ExchangePositionsButton(
				bleManager: bleManager,
				node: node
			)

			if let connectedNode {
				DeleteNodeButton(
					context: context,
					bleManager: bleManager,
					nodeConfig: nodeConfig,
					connectedNode: connectedNode,
					node: node
				)
			}
		}
	}

	@ViewBuilder
	private func admin(node: NodeInfoEntity, metadata: DeviceMetadataEntity) -> some View {
		if let user = node.user, let myInfo = node.myInfo, myInfo.hasAdmin {
			Button {
				let adminMessageId = nodeConfig.requestDeviceMetadata(
					to: user,
					from: user,
					index: myInfo.adminIndex,
					context: context
				)

				if adminMessageId > 0 {
					Logger.mesh.info("Sent node metadata request from node details")
				}
			} label: {
				Label {
					Text("Refresh Device Metadata")
				} icon: {
					Image(systemName: "arrow.clockwise")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}
			}
		}

		Button {
			showingRebootConfirm = true
		} label: {
			Label {
				Text("Reboot")
			} icon: {
				Image(systemName: "arrow.triangle.2.circlepath")
					.symbolRenderingMode(.monochrome)
					.foregroundColor(.accentColor)
			}
		}.confirmationDialog(
			"are.you.sure",
			isPresented: $showingRebootConfirm
		) {
			Button("reboot.node", role: .destructive) {
				if !nodeConfig.sendReboot(
					fromUser: node.user!,
					toUser: node.user!,
					adminIndex: node.myInfo!.adminIndex
				) {
					Logger.mesh.warning("Reboot Failed")
				}
			}
		}

		if metadata.canShutdown {
			Button {
				showingShutdownConfirm = true
			} label: {
				Label {
					Text("Shut Down")
				} icon: {
					Image(systemName: "power")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}
			}.confirmationDialog(
				"are.you.sure",
				isPresented: $showingShutdownConfirm
			) {
				Button("Shut Down Node?", role: .destructive) {
					if !nodeConfig.sendShutdown(
						fromUser: node.user!,
						toUser: node.user!,
						adminIndex: node.myInfo!.adminIndex
					) {
						Logger.mesh.warning("Shutdown Failed")
					}
				}
			}
		}
	}
}
