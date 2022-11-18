//
//  Contacts.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/21/21.
//

import SwiftUI
import CoreData

struct Contacts: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@ObservedObject private var userSettings: UserSettings = UserSettings()
	
	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "longName", ascending: true)],
		animation: .default)
	
	private var users: FetchedResults<UserEntity>
	@State var node: NodeInfoEntity? = nil
	
	@State private var selection: UserEntity? = nil // Nothing selected by default.

    var body: some View {

		NavigationSplitView {
			List {
				Section(header: Text("Channels (groups)")) {
					// Display Contacts for the rest of the non admin channels
					if node != nil && node!.myInfo != nil && node!.myInfo!.channels != nil {
						ForEach(node!.myInfo!.channels!.array as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in
							if channel.name?.lowercased() ?? "" != "admin" && channel.name?.lowercased() ?? "" != "gpio" {
								VStack {
									NavigationLink(destination: ChannelMessageList(channel: channel)) {
							
										let mostRecent = channel.allPrivateMessages.last
										let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
										let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
										let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
										HStack {
											VStack(alignment: .leading) {
												HStack {
													CircleText(text: String(channel.index), color: .gray, circleSize: 52, fontSize: 40)
														.padding(.trailing, 5)
													VStack {
														HStack {
															Text(String(channel.name ?? "Channel \(channel.index)").camelCaseToWords()).font(.headline)
															Spacer()
															if channel.allPrivateMessages.count > 0 {
																VStack (alignment: .trailing) {
																	if lastMessageDay == currentDay {
																		Text(lastMessageTime, style: .time )
																			.font(.subheadline)
																	} else if  lastMessageDay == (currentDay - 1) {
																		Text("Yesterday")
																			.font(.subheadline)
																	} else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
																		Text(lastMessageTime.formattedDate(format: "MM/dd/yy"))
																			.font(.subheadline)
																	} else if lastMessageDay < (currentDay - 1800) {
																		Text(lastMessageTime.formattedDate(format: "MM/dd/yy"))
																			.font(.subheadline)
																	}
																}
																.brightness(-0.20)
															}
														}
														if channel.allPrivateMessages.count > 0 {
															HStack(alignment: .top) {
																Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
																	.truncationMode(.tail)
																	.frame(maxWidth: .infinity, alignment: .leading)
																	.brightness(-0.20)
																	.font(.body)
															}
														}
													}
													.frame(maxWidth: .infinity, alignment: .leading)
												}
											}
										}
									}
								}
								.frame(maxWidth: .infinity, maxHeight: 80, alignment: .leading)
							}
						}
						.padding(.top, 10)
						.padding(.bottom, 10)
					}
				}
				Section(header: Text("Direct Messages")) {
					ForEach(users) { (user: UserEntity) in
						if  user.num != bleManager.userSettings?.preferredNodeNum ?? 0 {
							NavigationLink(destination: UserMessageList(user: user)) {
								let mostRecent = user.num == bleManager.broadcastNodeNum ? user.messageList.last : user.messageList.last(where: { $0.toUser?.num ?? 0 !=  bleManager.broadcastNodeNum })
								let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
								let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
								let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
								HStack {
									VStack {
										HStack {
											CircleText(text: user.shortName ?? "???", color: .gray, circleSize: 52, fontSize: 16)
												.padding(.trailing, 5)
											VStack {
												HStack {
													Text(user.longName ?? "Unknown").font(.headline)
													Spacer()
													if user.messageList.count > 0 {
														VStack (alignment: .trailing) {
															if lastMessageDay == currentDay {
																Text(lastMessageTime, style: .time )
																	.font(.subheadline)
															} else if  lastMessageDay == (currentDay - 1) {
																Text("Yesterday")
																	.font(.subheadline)
															} else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
																Text(lastMessageTime.formattedDate(format: "MM/dd/yy"))
																	.font(.subheadline)
															} else if lastMessageDay < (currentDay - 1800) {
																Text(lastMessageTime.formattedDate(format: "MM/dd/yy"))
																	.font(.subheadline)
															}
														}
														.brightness(-0.2)
													}
												}
												if user.messageList.count > 0 {
													HStack(alignment: .top) {
														Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
															.truncationMode(.tail)
															.font(.body)
															.frame(maxWidth: .infinity, alignment: .leading)
															.brightness(-0.2)
													}
												}
											}
											.frame(maxWidth: .infinity, maxHeight: 80, alignment: .leading)
										}
									}
								}
							}
							.padding(.top, 10)
							.padding(.bottom, 10)
						}
					}
				}
			}
			.navigationTitle("Contacts")
			.navigationBarItems(leading:
				MeshtasticLogo()
			)
			.onAppear {
				self.bleManager.userSettings = userSettings
				self.bleManager.context = context
				
				if userSettings.preferredNodeNum > 0 {
					
					let fetchNodeInfoRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest.init(entityName: "NodeInfoEntity")
					fetchNodeInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(userSettings.preferredNodeNum))
					
					do {
						
						let fetchedNode = try context.fetch(fetchNodeInfoRequest) as! [NodeInfoEntity]
						// Found a node, check it for a region
						if !fetchedNode.isEmpty {
							node = fetchedNode[0]
							
						}
					} catch {
						
					}
				}
				
			}
		}
		detail: {
			if let user = selection {
				UserMessageList(user:user)
				
			} else {
				Text("Select a Contact")
			}
		}
    }
}
