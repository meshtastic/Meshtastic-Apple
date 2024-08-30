import CoreData
import FirebaseAnalytics
import OSLog
import SwiftUI

struct NodeList: View {
	private let coreDataTools = CoreDataTools()
	private let detailInfoFont = Font.system(size: 14, weight: .regular, design: .rounded)
	private let detailIconSize: CGFloat = 16
	private let debounce = Debounce<() async -> Void>(duration: .milliseconds(500)) { action in
		await action()
	}

	@SceneStorage("selectedDetailView")
	private var selectedDetailView: String?
	@Environment(\.managedObjectContext)
	private var context
	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@EnvironmentObject
	private var bleManager: BLEManager
	@EnvironmentObject
	private var nodeConfig: NodeConfig
	@StateObject
	private var appState = AppState.shared

	@State
	private var selectedNode: NodeInfoEntity?
	@State
	private var favoriteNodes = 0
	@State
	private var onlineNodes = 0
	@State
	private var offlineNodes = 0
	@State
	private var loraNodes = 0
	@State
	private var loraSingleHopNodes = 0
	@State
	private var mqttNodes = 0
	@State
	private var searchText = ""

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "hopsAway", ascending: true),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var connectedNodeNum: Int64 {
		Int64(bleManager.deviceConnected?.num ?? 0)
	}
	private var connectedNode: NodeInfoEntity? {
		coreDataTools.getNodeInfo(
			id: connectedNodeNum,
			context: context
		)
	}
	private var suggestedNodes: [NodeInfoEntity] {
		let connectedNodeNum = Int(bleManager.deviceConnected?.num ?? 0)
		return nodes.filter { node in
			node.num != connectedNodeNum
			&& (node.favorite
				|| (node.isOnline && !node.viaMqtt && node.hopsAway == 0))
		}
	}

	var body: some View {
		NavigationStack {
			List(selection: $selectedNode) {
				summary
				suggestedList
				nodeList(online: true)
				nodeList(online: false)
			}
			.listStyle(.automatic)
			.searchable(
				text: $searchText,
				placement: .automatic,
				prompt: "Find a node"
			)
			.disableAutocorrection(true)
			.scrollDismissesKeyboard(.interactively)
			.navigationTitle("Nodes")
			.navigationBarItems(
				trailing: ConnectedDevice()
			)
		}
		.onAppear {
			Analytics.logEvent(
				AnalyticEvents.nodeList.id,
				parameters: [
					"nodes_in_list": nodes.count
				]
			)
		}
		.onChange(of: nodes, initial: true) {
			debounce.emit {
				await countNodes()
			}
		}
		.onChange(of: bleManager.deviceConnected, initial: true) {
			debounce.emit {
				await countNodes()
			}
		}
		.onChange(of: searchText, initial: true) {
			Task {
				await updateFilter()
			}
		}
		.onChange(of: appState.navigationPath, initial: true) {
			guard let navigationPath = appState.navigationPath else {
				return
			}

			if navigationPath.hasPrefix("meshtastic:///nodes") {
				if let urlComponent = URLComponents(string: navigationPath) {
					let queryItems = urlComponent.queryItems
					let nodeNum = queryItems?.first(where: {
						$0.name == "nodenum"
					})?.value

					if nodeNum == nil {
						Logger.data.debug("nodeNum not found")
					}
					else {
						selectedNode = nodes.first(where: {
							$0.num == Int64(nodeNum ?? "-1")
						})
						AppState.shared.navigationPath = nil
					}
				}
			}
		}
	}

	@ViewBuilder
	private var summary: some View {
		VStack(alignment: .leading, spacing: 4) {
			connectedNodeListItem

			Divider()
				.foregroundColor(.gray)

			Text("Online: \(onlineNodes) nodes")
				.font(.system(size: 12, weight: .regular))
				.foregroundColor(colorScheme == .dark ? .white : .black)

			VStack(alignment: .leading, spacing: 4) {
				HStack(alignment: .center, spacing: 4) {
					Image(systemName: "minus")
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Image(systemName: "star.circle")
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Text(String(favoriteNodes))
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)
				}

				HStack(alignment: .center, spacing: 4) {
					Image(systemName: "minus")
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Image(systemName: "antenna.radiowaves.left.and.right.circle")
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Text(String(loraNodes))
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Spacer()
						.frame(width: 4)

					Image(systemName: "1.circle")
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Text(String(loraSingleHopNodes))
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Spacer()
						.frame(width: 4)

					Image(systemName: "plus.circle")
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Text(String(loraNodes - loraSingleHopNodes))
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)
				}

				HStack(alignment: .center, spacing: 4) {
					Image(systemName: "minus")
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Image(systemName: "network")
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)

					Text(String(mqttNodes))
						.font(.system(size: 12, weight: .light))
						.foregroundColor(.gray)
				}
			}

			Divider()
				.foregroundColor(.gray)

			Text("Offline: \(offlineNodes) nodes")
				.font(.system(size: 12, weight: .regular))
				.foregroundColor(colorScheme == .dark ? .white : .black)
		}
	}

	@ViewBuilder
	private var suggestedList: some View {
		Section(
			header: listHeader(
				title: "Favorites & Reachable",
				nodesCount: suggestedNodes.count
			)
		) {
			ForEach(suggestedNodes, id: \.num) { node in
				NodeListItem(
					node: node,
					connected: connectedNodeNum == node.num,
					connectedNode: connectedNodeNum
				)
				.contextMenu {
					contextMenuActions(
						node: node,
						connectedNode: connectedNode
					)
				}
			}
		}
		.headerProminence(.increased)
	}

	@ViewBuilder
	private var connectedNodeListItem: some View {
		NavigationLink {
			if let connectedNode {
				NodeDetail(node: connectedNode)
			}
			else {
				Connect()
			}
		} label: {
			HStack(alignment: .top) {
				connectedNodeAvatar

				VStack(alignment: .leading, spacing: 4) {
					if let connectedNode {
						Text(connectedNode.user?.longName ?? "Unknown")
							.lineLimit(2)
							.fontWeight(.medium)
							.font(.title2)

						BatteryView(
							node: connectedNode,
							withLabels: true
						)

						let deviceMetrics = connectedNode.telemetries?.filtered(
							using: NSPredicate(format: "metricsType == 0")
						)
						let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity

						if let channelUtil = mostRecent?.channelUtilization {
							let chUtilFormatted = String(format: "%.2f", channelUtil) + "%"

							HStack {
								Image(systemName: "arrow.left.arrow.right.circle.fill")
									.font(detailInfoFont)
									.foregroundColor(.gray)

								Text("Channel: " + chUtilFormatted)
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}
						}

						if let airUtilTx = mostRecent?.airUtilTx {
							let airUtilFormatted = String(format: "%.2f", airUtilTx) + "%"

							HStack {
								Image(systemName: "wave.3.right.circle.fill")
									.font(detailInfoFont)
									.foregroundColor(.gray)

								Text("Air Time: " + airUtilFormatted)
									.font(detailInfoFont)
									.foregroundColor(.gray)
							}
						}
					}
					else {
						Text("Not connected")
							.lineLimit(1)
							.fontWeight(.medium)
							.font(.title2)
					}
				}
				.frame(alignment: .leading)
			}
		}
	}

	@ViewBuilder
	private var connectedNodeAvatar: some View {
		ZStack(alignment: .top) {
			if let connectedNode {
				AvatarNode(
					connectedNode,
					size: 64
				)
				.padding([.top, .bottom, .trailing], 10)

				HStack(spacing: 0) {
					Spacer()

					Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(.listBackground(for: colorScheme))
						)
				}
			}
			else {
				AvatarAbstract(
					size: 64
				)
				.padding([.top, .bottom, .trailing], 10)
			}
		}
		.frame(width: 80, height: 80)
	}

	@ViewBuilder
	private func nodeList(online: Bool = true) -> some View {
		let nodeList = nodes.filter { node in
			node.num != connectedNodeNum && !suggestedNodes.contains(node) && node.isOnline == online
		}

		if !nodeList.isEmpty {
			Section(
				header: listHeader(
					title: online ? "Online" : "Offline",
					nodesCount: nodeList.count
				)
			) {
				let connectedNode = nodes.first(where: {
					$0.num == connectedNodeNum
				})

				ForEach(nodeList, id: \.num) { node in
					NodeListItem(
						node: node,
						connected: bleManager.deviceConnected?.num ?? -1 == node.num,
						connectedNode: bleManager.deviceConnected?.num ?? -1
					)
					.contextMenu {
						contextMenuActions(
							node: node,
							connectedNode: connectedNode
						)
					}
				}
			}
			.headerProminence(.increased)
		}
		else {
			EmptyView()
		}
	}

	@ViewBuilder
	private func listHeader(title: String, nodesCount: Int) -> some View {
		HStack(alignment: .center) {
			Text(title)
				.fontDesign(.rounded)

			Spacer()

			Text(String(nodesCount))
				.fontDesign(.rounded)
		}
	}

	@ViewBuilder
	private func contextMenuActions(
		node: NodeInfoEntity,
		connectedNode: NodeInfoEntity?
	) -> some View {
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

	private func countNodes() async {
		var onlineNodes = 0
		var offlineNodes = 0
		var favoriteNodes = 0
		var loraNodes = 0
		var loraSingleHopNodes = 0
		var mqttNodes = 0

		for node in nodes {
			if node.isOnline {
				onlineNodes += 1

				if node.favorite {
					favoriteNodes += 1
				}

				if node.viaMqtt {
					mqttNodes += 1
				}
				else {
					loraNodes += 1

					if node.hopsAway == 1 {
						loraSingleHopNodes += 1
					}
				}
			}
			else {
				offlineNodes += 1
			}
		}

		self.onlineNodes = onlineNodes
		self.offlineNodes = offlineNodes
		self.favoriteNodes = favoriteNodes
		self.loraNodes = loraNodes
		self.loraSingleHopNodes = loraSingleHopNodes
		self.mqttNodes = mqttNodes

		Analytics.logEvent(
			AnalyticEvents.nodeListCount.id,
			parameters: [
				"nodes_online": onlineNodes,
				"nodes_offline": offlineNodes,
				"nodes_favorite": favoriteNodes,
				"nodes_lora": loraNodes,
				"nodes_lora_single_hop": loraSingleHopNodes,
				"nodes_mqtt": mqttNodes
			]
		)
	}

	private func updateFilter() async {
		let searchPredicates = [
			"user.userId",
			"user.numString",
			"user.hwModel",
			"user.longName",
			"user.shortName"
		].map { property in
			NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
		}

		if !searchText.isEmpty {
			nodes.nsPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
		}
		else {
			nodes.nsPredicate = nil
		}
	}
}

extension FetchedResults<NodeInfoEntity>: Equatable {
	public static func == (
		lhs: FetchedResults<NodeInfoEntity>,
		rhs: FetchedResults<NodeInfoEntity>
	) -> Bool {
		lhs.elementsEqual(rhs)
	}
}
