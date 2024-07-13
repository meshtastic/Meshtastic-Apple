import SwiftUI
import WeatherKit
import MapKit
import CoreLocation
import OSLog

struct NodeDetail: View {
	var columnVisibility = NavigationSplitViewVisibility.all

	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@ObservedObject
	var node: NodeInfoEntity

	private let relativeFormatter: RelativeDateTimeFormatter = {
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
	private var nodeTelemetry: TelemetryEntity? {
		node
			.telemetries?
			.filtered(
				using: NSPredicate(format: "metricsType == 0")
			)
			.lastObject
		as? TelemetryEntity
	}

	var body: some View {
		NavigationStack {
			List {
				Section("Hardware") {
					hardwareInfo
				}

				Section("Node") {
					nodeInfo
				}

				Section("Logs") {
					logs
				}

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
				NavigationLink {
					NodeMapView(node: node)
				} label: {
					SimpleNodeMapView(node: node)
						.frame(width: .infinity, height: 200)
						.cornerRadius(8)
						.padding(.top, 8)
						.disabled(true)
				}
			}
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
						.symbolRenderingMode(.multicolor)
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
						.symbolRenderingMode(.multicolor)
				}

				Spacer()

				Text(deviceRole.name)
			}
		}

		if let metadata = node.metadata, let firmwareVersion = metadata.firmwareVersion {
			HStack {
				Label {
					Text("Firmware")
				} icon: {
					Image(systemName: "memorychip")
						.symbolRenderingMode(.multicolor)
				}

				Spacer()

				Text("v" + firmwareVersion)
			}
		}

		if
			let firstHeard = node.firstHeard,
			firstHeard.timeIntervalSince1970 > 0,
			let firstHeardFormatted = relativeFormatter.string(for: firstHeard)
		{
			HStack {
				Label {
					Text("First Heard")
				} icon: {
					Image(systemName: "clock")
						.symbolRenderingMode(.multicolor)
				}

				Spacer()

				Text(firstHeardFormatted)
					.textSelection(.enabled)
			}
		}

		if
			let lastHeard = node.lastHeard,
			lastHeard.timeIntervalSince1970 > 0 ,
			let lastHeardFormatted = relativeFormatter.string(for: lastHeard)
		{
			HStack {
				Label {
					Text("Last Heard")
				} icon: {
					Image(systemName: "clock.arrow.circlepath")
						.symbolRenderingMode(.multicolor)
				}

				Spacer()

				Text(lastHeardFormatted)
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
						.symbolRenderingMode(.multicolor)
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
						.symbolRenderingMode(.multicolor)
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
						.symbolRenderingMode(.multicolor)
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
						.symbolRenderingMode(.multicolor)
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
						.symbolRenderingMode(.multicolor)
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
						.symbolRenderingMode(.multicolor)
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
						.symbolRenderingMode(.multicolor)
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
					.symbolRenderingMode(.multicolor)
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
						.symbolRenderingMode(.multicolor)
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
