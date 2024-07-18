import SwiftUI
import OSLog

struct NodeList: View {
	@SceneStorage("selectedDetailView")
	var selectedDetailView: String?
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@StateObject
	var appState = AppState.shared

	@State
	private var columnVisibility = NavigationSplitViewVisibility.all
	@State
	private var selectedNode: NodeInfoEntity?
	@State
	private var searchText = ""

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var connectedNode: NodeInfoEntity? {
		getNodeInfo(
			id: connectedNodeNum,
			context: context
		)
	}
	private var connectedNodeNum: Int64 {
		Int64(bleManager.connectedPeripheral?.num ?? 0)
	}
	private var suggestedNodes: [NodeInfoEntity] {
		let connectedNodeNum = Int(bleManager.connectedPeripheral?.num ?? 0)
		return nodes.filter { node in
				node.favorite
				|| node.num == connectedNodeNum
				|| (node.isOnline && !node.viaMqtt && node.hopsAway == 0)
		}
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			List(selection: $selectedNode) {
				suggestedList()
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
			.scrollDismissesKeyboard(.immediately)
			.navigationTitle("Nodes")
			.navigationSplitViewColumnWidth(min: 100, ideal: 250, max: 500)
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ConnectedDevice(ble: bleManager)
			)
		} content: {
			if let node = selectedNode {
				NavigationStack {
					NodeDetail(
						columnVisibility: columnVisibility,
						node: node
					)
					.edgesIgnoringSafeArea([.leading, .trailing])
					.navigationBarItems(
						trailing: ConnectedDevice(ble: bleManager)
					)
				}
			} else {
				ContentUnavailableView("select.node", systemImage: "flipphone")
			}
		} detail: {
			ContentUnavailableView(
				"Can't load node info",
				systemImage: "slash.circle"
			)
		}
		.navigationSplitViewStyle(.balanced)
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}

			Task {
				await updateFilter()
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

			if navigationPath.hasPrefix("meshtastic://nodes") {
				if let urlComponent = URLComponents(string: navigationPath) {
					let queryItems = urlComponent.queryItems
					let nodeNum = queryItems?.first(where: {
						$0.name == "nodenum"
					})?.value

					if nodeNum == nil {
						Logger.data.debug("nodeNum not found")
					} else {
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
	private func suggestedList() -> some View {
		Section(
			header: listHeader(
				title: "In Case of Apocalypse",
				nodesCount: suggestedNodes.count
			)
		) {
			ForEach(suggestedNodes, id: \.self) { node in
				NodeListItem(
					node: node,
					connected: connectedNodeNum == node.num,
					connectedNode: connectedNodeNum,
					showBattery: true
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
	private func nodeList(online: Bool = true) -> some View {
		let nodeList = nodes.filter { node in
			!suggestedNodes.contains(node) &&  node.isOnline == online
		}

		Section(
			header: listHeader(
				title: online ? "Online" : "Offline",
				nodesCount: nodeList.count
			)
		) {
			let connectedNode = nodes.first(where: {
				$0.num == connectedNodeNum
			})

			ForEach(nodeList, id: \.self) { node in
				NodeListItem(
					node: node,
					connected: bleManager.connectedPeripheral?.num ?? -1 == node.num,
					connectedNode: bleManager.connectedPeripheral?.num ?? -1
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
				bleManager: bleManager,
				context: context,
				connectedNode: connectedNode,
				node: node
			)
		}
	}

	private func updateFilter() async {
		let searchPredicates = [
			"user.userId",
			"user.numString",
			"user.hwModel",
			"user.longName",
			"user.shortName"
		].map { property in
			return NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
		}

		if !searchText.isEmpty {
			nodes.nsPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
		}
		else {
			nodes.nsPredicate = nil
		}
	}
}
