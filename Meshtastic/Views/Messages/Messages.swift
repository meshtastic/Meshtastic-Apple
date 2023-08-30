//
//  Messages.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData

struct Messages: View {

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
					Text("channels")
						.font(.title2)
				}
				NavigationLink {
					UserList(node: node)
				} label: {
					Image(systemName: "person")
						.symbolRenderingMode(.hierarchical)
						.foregroundColor(.accentColor)
						.brightness(0.2)
					Text("direct.messages")
						.font(.title2)
				}
			}
			.navigationTitle("messages")
			.navigationBarItems(leading: MeshtasticLogo())
			.onAppear {
				self.bleManager.context = context
				if UserDefaults.preferredPeripheralId.count > 0 {
					let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
					fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(bleManager.connectedPeripheral?.num ?? -1))
					do {
						guard let fetchedNode = try context.fetch(fetchNodeInfoRequest) as? [NodeInfoEntity] else {
							return
						}
						// Found a node, check it for a region
						if !fetchedNode.isEmpty {
							node = fetchedNode[0]
						}
					} catch {

					}
				}
			}
			
		} content: {

		} detail: {

		}
	}
}
