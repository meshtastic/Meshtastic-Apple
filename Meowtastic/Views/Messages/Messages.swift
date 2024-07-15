import SwiftUI
import CoreData
import OSLog

struct Messages: View {
	@StateObject
	var appState = AppState.shared
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager
	@State
	var node: NodeInfoEntity?

	@State
	private var userSelection: UserEntity? // Nothing selected by default.
	@State
	private var channelSelection: ChannelEntity? // Nothing selected by default.
	@State
	private var columnVisibility = NavigationSplitViewVisibility.all

	enum MessagesSidebar {
		case groupMessages
		case directMessages
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			List {
				NavigationLink {
					ChannelList(node: node)
				} label: {
					HStack(spacing: 8) {
						Image(systemName: "person.3.fill")
							.font(.title2)
							.symbolRenderingMode(.monochrome)
							.foregroundColor(.accentColor)
							.frame(width: 48, height: 48)

						Text("Channels")
							.font(.headline)
							.badge(appState.unreadChannelMessages)
					}
				}

				NavigationLink {
					UserList(node: node)
				} label: {
					HStack(spacing: 8) {
						Image(systemName: "message.fill")
							.font(.title2)
							.symbolRenderingMode(.monochrome)
							.foregroundColor(.accentColor)
							.frame(width: 48, height: 48)

						Text("Direct Messages")
							.font(.headline)
							.badge(appState.unreadDirectMessages)
					}
				}
			}
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}

				if UserDefaults.preferredPeripheralId.count > 0 {
					let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
					fetchNodeInfoRequest.predicate = NSPredicate(
						format: "num == %lld",
						Int64(UserDefaults.preferredPeripheralNum)
					)

					let fetchedNode = try? context.fetch(fetchNodeInfoRequest)
					if let fetchedNode, !fetchedNode.isEmpty {
						node = fetchedNode[0]
					}
				}
			}
			.onChange(of: appState.navigationPath, initial: true) {
				if (appState.navigationPath?.hasPrefix("meshtastic://messages")) != nil {
					if let urlComponent = URLComponents(string: appState.navigationPath ?? "") {
						let queryItems = urlComponent.queryItems
						let channel = queryItems?.first(where: {
							$0.name == "channel"
						})?.value

						if let channel {
							Logger.services.info("Deep Link Channel \(channel)")
						} else {
							Logger.services.info("Channel Deep Link not found")
						}
					}
				}
			}
			.navigationTitle("Messages")
			.navigationBarTitleDisplayMode(.large)
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ConnectedDevice(ble: bleManager)
			)
		} content: { } detail: { }
	}
}
