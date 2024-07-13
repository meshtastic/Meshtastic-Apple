import SwiftUI
import CoreLocation
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
	var isEditingFilters = false

	@State
	private var columnVisibility = NavigationSplitViewVisibility.all
	@State
	private var selectedNode: NodeInfoEntity?
	@State
	private var searchText = ""
	@State
	private var isFavorite = UserDefaults.filterFavorite
	@State
	private var isOnline = UserDefaults.filterOnline
	@State
	private var ignoreMQTT = UserDefaults.ignoreMQTT

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true),
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	@ViewBuilder
	func contextMenuActions(
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

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			nodeList
		} content: {
			if let node = selectedNode {
				NavigationStack {
					NodeDetail(
						columnVisibility: columnVisibility,
						node: node
					)
					.edgesIgnoringSafeArea([.leading, .trailing])
					.navigationBarTitle(
						String(node.user?.longName ?? "unknown".localized),
						displayMode: .inline
					)
					.navigationBarItems(
						trailing: ConnectedDevice(ble: bleManager)
					)
				}

			 } else {
				 ContentUnavailableView("select.node", systemImage: "flipphone")
			 }
		} detail: {
			ContentUnavailableView("", systemImage: "line.3.horizontal")
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
		.onChange(of: isFavorite, initial: false) {
			Task {
				await updateFilter()
			}
		}
		.onChange(of: isOnline, initial: false) {
			Task {
				await updateFilter()
			}
		}
		.onChange(of: ignoreMQTT, initial: false) {
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
	private var nodeList: some View {
		let connectedNodeNum = Int(bleManager.connectedPeripheral?.num ?? 0)
		let connectedNode = nodes.first(where: {
			$0.num == connectedNodeNum
		})

		List(
			nodes.filter { node in
				guard isFavorite || isOnline || ignoreMQTT else {
					return true
				}

				if (isFavorite && node.favorite)
					|| (isOnline && node.isOnline)
					|| (ignoreMQTT && !node.viaMqtt)
				{
					return true
				}

				return false
			},
			id: \.self,
			selection: $selectedNode
		) { node in
			NodeListItem(
				connected: bleManager.connectedPeripheral?.num ?? -1 == node.num,
				connectedNode: bleManager.connectedPeripheral?.num ?? -1,
				node: node
			)
			.contextMenu {
				contextMenuActions(
					node: node,
					connectedNode: connectedNode
				)
			}
		}
		.sheet(isPresented: $isEditingFilters) {
			NodeListFilter(
				isFavorite: $isFavorite,
				isOnline: $isOnline,
				ignoreMQTT: $ignoreMQTT
			)
		}
		.safeAreaInset(edge: .bottom, alignment: .trailing) {
			HStack {
				Button(action: {
					withAnimation {
						isEditingFilters = !isEditingFilters
					}
				}) {
					Image(
						systemName: !isEditingFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
					)
						.padding(.vertical, 5)
				}
				.tint(Color(UIColor.secondarySystemBackground))
				.foregroundColor(.accentColor)
				.buttonStyle(.borderedProminent)
			}
			.controlSize(.regular)
			.padding(5)
		}
		.padding(.bottom, 5)
		.listStyle(.plain)
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
	}

	private func updateFilter() async {
		UserDefaults.filterFavorite = isFavorite
		UserDefaults.filterOnline = isOnline
		UserDefaults.ignoreMQTT = ignoreMQTT

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
