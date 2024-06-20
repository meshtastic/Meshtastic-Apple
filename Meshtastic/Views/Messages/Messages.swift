//
//  Messages.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData
import OSLog
#if canImport(TipKit)
import TipKit
#endif

struct Messages: View {

	@StateObject var appState = AppState.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State var node: NodeInfoEntity?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var channelSelection: ChannelEntity? // Nothing selected by default.

	@State private var columnVisibility = NavigationSplitViewVisibility.all

	enum MessagesSidebar {
		case groupMessages
		case directMessages
	}

	var body: some View {

		NavigationSplitView(columnVisibility: $columnVisibility) {
			// Sidebar
			List {
				NavigationLink {
					ChannelList(node: node)
				} label: {
					Image(systemName: "person.3")
						.symbolRenderingMode(.hierarchical)
						.foregroundColor(.accentColor)
						.brightness(0.2)
						.font(.title)
					Text("channels")
						.font(.title2)
						.badge(appState.unreadChannelMessages)
						.padding(.vertical)
				}
				NavigationLink {
					UserList(node: node)
				} label: {
					Image(systemName: "person.circle")
						.symbolRenderingMode(.hierarchical)
						.foregroundColor(.accentColor)
						.brightness(0.2)
						.font(.largeTitle)
					Text("direct.messages")
						.font(.title2)
						.badge(appState.unreadDirectMessages)
						.padding(.vertical)
				}
				if #available(iOS 17.0, macOS 14.0, *) {
					TipView(MessagesTip(), arrowEdge: .top)
				}
			}
			.navigationTitle("messages")
			.navigationBarTitleDisplayMode(.large)
			.navigationBarItems(leading: MeshtasticLogo())
			.onChange(of: (appState.navigationPath)) { newPath in

				if (newPath?.hasPrefix("meshtastic://messages")) != nil {

					if let urlComponent = URLComponents(string: newPath ?? "") {
						let queryItems = urlComponent.queryItems
						let channel = queryItems?.first(where: { $0.name == "channel" })?.value

						if let channel {
							Logger.services.info("Deep Link Channel \(channel)")
							//	selectedNode = nodes.first(where: { $0.num == Int64(nodeNum ?? "-1") })
							//	AppState.shared.navigationPath = nil
						} else {
							Logger.services.info("Channel Deep Link not found")
						}
					}
				}
			}
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}
				if UserDefaults.preferredPeripheralId.count > 0 {
					let fetchNodeInfoRequest = NodeInfoEntity.fetchRequest()
					fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(UserDefaults.preferredPeripheralNum))
					do {
						node = try context.fetch(fetchNodeInfoRequest).first
					} catch {
						Logger.data.error("💥 Error fetching Node Info: \(error.localizedDescription)")
					}
				}
			}

		} content: {

		} detail: {

		}
	}
}
