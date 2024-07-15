import SwiftUI
import MapKit
import CoreLocation
import OSLog

struct NodeDetail: View {
	var isInSheet = false
	var columnVisibility = NavigationSplitViewVisibility.all

	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@ObservedObject
	var node: NodeInfoEntity

	private let distanceFormatter = MKDistanceFormatter()
	private let detailInfoFont = Font.system(size: 12, weight: .regular, design: .rounded)
	private let detailIconSize: CGFloat = 12
	private let relativeDateFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full

		return formatter
	}()

	@State
	private var showingShutdownConfirm: Bool = false
	@State
	private var showingRebootConfirm: Bool = false

	private var connectedNode: NodeInfoEntity? {
		getNodeInfo(
			id: bleManager.connectedPeripheral?.num ?? -1,
			context: context
		)
	}
	private var nodePosition: PositionEntity? {
		node.positions?.lastObject as? PositionEntity
	}
	private var nodeTelemetry: TelemetryEntity? {
		node
			.telemetries?
			.filtered(
				using: NSPredicate(format: "metricsType == 0")
			)
			.lastObject
		as? TelemetryEntity
	}
	private var hasAnyLog: Bool {
		if
			node.hasDeviceMetrics,
			node.hasEnvironmentMetrics,
			node.hasDetectionSensorMetrics,
			node.hasPax,
			let routes = node.traceRoutes, routes.count > 0
		{
			return true
		}

		return false
	}

	var body: some View {
		NavigationStack {
			List {
				Section("Info") {
					hardwareInfo
				}

				Section("Details") {
					nodeInfo
				}

				if hasAnyLog {
					Section("Logs") {
						logs
					}
				}

				if !isInSheet {
					Section("Actions") {
						actions
					}

					if
						let connectedNode,
						let nodeMetadata = node.metadata,
						self.bleManager.connectedPeripheral != nil
					{
						Section("Administration") {
							admin(node: connectedNode, metadata: nodeMetadata)
						}
					}
				}
			}
			.listStyle(.insetGrouped)
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}
			}
		}
	}

	@ViewBuilder
	private var hardwareInfo: some View {
		VStack {
			NodeInfoView(node: node)

			if node.hasPositions {
				if isInSheet {
					VStack(alignment: .leading, spacing: 8) {
						SimpleNodeMapView(node: node)
							.frame(width: .infinity, height: 120)
							.cornerRadius(8)
							.padding(.top, 8)
							.disabled(true)
							.toolbar(.hidden)

						locationInfo
							.padding(.horizontal, 8)
					}
				}
				else {
					NavigationLink {
						NodeMapView(node: node)
					} label: {
						VStack(alignment: .leading, spacing: 8) {
							SimpleNodeMapView(node: node)
								.frame(width: .infinity, height: 200)
								.cornerRadius(8)
								.padding(.top, 8)
								.disabled(true)

							locationInfo
								.padding(.horizontal, 8)
						}
					}
				}
			}
		}
	}

	@ViewBuilder
	private var locationInfo: some View {
		if let position = nodePosition {
			HStack(alignment: .center, spacing: 8) {
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
						.frame(width: 8)

					Image(systemName: "safari")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
					
					Text(headingFormatted)
						.font(detailInfoFont)
						.foregroundColor(.gray)
					
					Spacer()
						.frame(width: 8)
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
						.frame(width: 8)

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
	private var nodeInfo: some View {
		if let userID = node.user?.userId {
			HStack {
				Label {
					Text("User ID")
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

		if
			let lastHeard = node.lastHeard,
			lastHeard.timeIntervalSince1970 > 0 ,
			let lastHeardFormatted = relativeDateFormatter.string(for: lastHeard)
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

				Text(lastHeardFormatted)
					.textSelection(.enabled)
			}
		}

		if
			let firstHeard = node.firstHeard,
			firstHeard.timeIntervalSince1970 > 0,
			let firstHeardFormatted = relativeDateFormatter.string(for: firstHeard)
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

				Text(firstHeardFormatted)
					.textSelection(.enabled)
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
	private var logs: some View {
		if node.hasDeviceMetrics {
			NavigationLink {
				DeviceMetricsLog(node: node)
			} label: {
				Label {
					Text("Device Metrics Log")
				} icon: {
					Image(systemName: "flipphone")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}
			}
		}

		if node.hasEnvironmentMetrics {
			NavigationLink {
				EnvironmentMetricsLog(node: node)
			} label: {
				Label {
					Text("Environment Metrics Log")
				} icon: {
					Image(systemName: "cloud.sun.rain")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}
			}
		}

		if let routes = node.traceRoutes, routes.count > 0 {
			NavigationLink {
				TraceRouteLog(node: node)
			} label: {
				Label {
					Text("Trace Route Log")
				} icon: {
					Image(systemName: "signpost.right.and.left")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}
			}
		}

		if node.hasDetectionSensorMetrics {
			NavigationLink {
				DetectionSensorLog(node: node)
			} label: {
				Label {
					Text("Detection Sensor Log")
				} icon: {
					Image(systemName: "sensor")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}
			}
		}

		if node.hasPax {
			NavigationLink {
				PaxCounterLog(node: node)
			} label: {
				Label {
					Text("PAX Counter")
				} icon: {
					Image(systemName: "figure.walk.motion")
						.symbolRenderingMode(.monochrome)
						.foregroundColor(.accentColor)
				}
			}
		}
	}

	@ViewBuilder
	private var actions: some View {
		FavoriteNodeButton(
			bleManager: bleManager,
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
			let connectedPeripheral = bleManager.connectedPeripheral,
			node.num != connectedPeripheral.num
		{
			ExchangePositionsButton(
				bleManager: bleManager,
				node: node
			)

			TraceRouteButton(
				bleManager: bleManager,
				node: node
			)

			if let connectedNode {
				if node.isStoreForwardRouter {
					ClientHistoryButton(
						bleManager: bleManager,
						connectedNode: connectedNode,
						node: node
					)
				}

				DeleteNodeButton(
					bleManager: bleManager,
					context: context,
					connectedNode: connectedNode,
					node: node
				)
			}
		}
	}

	@ViewBuilder
	private func admin(node: NodeInfoEntity, metadata: DeviceMetadataEntity) -> some View {
		if let myInfo = node.myInfo, myInfo.hasAdmin {
			Button {
				let adminMessageId = bleManager.requestDeviceMetadata(
					fromUser: node.user!,
					toUser: node.user!,
					adminIndex: node.myInfo!.adminIndex,
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
				if !bleManager.sendReboot(
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
					if !bleManager.sendShutdown(
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
