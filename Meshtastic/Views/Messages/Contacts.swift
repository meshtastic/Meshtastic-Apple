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

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "lastMessage", ascending: true)],
		animation: .default)

	private var users: FetchedResults<UserEntity>
	@State var node: NodeInfoEntity?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var channelSelection: ChannelEntity? // Nothing selected by default.
	@State private var isPresentingDeleteChannelMessagesConfirm: Bool = false
	@State private var isPresentingDeleteUserMessagesConfirm: Bool = false
	@State private var isPresentingTraceRouteSentAlert = false

    var body: some View {

		NavigationSplitView {
			let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
			let dateFormatString = (localeDateFormat ?? "MM/dd/YY")
			List {
				Section(header: Text("channels")) {
					// Display Contacts for the rest of the non admin channels
					if node != nil && node!.myInfo != nil && node!.myInfo!.channels != nil {
						ForEach(node!.myInfo!.channels!.array as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in
							if channel.name?.lowercased() ?? "" != "admin" && channel.name?.lowercased() ?? "" != "gpio" && channel.name?.lowercased() ?? "" != "serial" {

								NavigationLink(destination: ChannelMessageList(channel: channel)) {

									let mostRecent = channel.allPrivateMessages.last(where: { $0.channel == channel.index })
									let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
									let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
									let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0

									
									ZStack {
										Image(systemName: "circle.fill")
											.opacity(channel.allPrivateMessages.count > 0 ? 1 : 0)
											.font(.system(size: 10))
											.foregroundColor(.accentColor)
											.brightness(0.2)
									}
									CircleText(text: String(channel.index), color: .accentColor, circleSize: 45, fontSize: 40)
										.brightness(0.2)
									
									VStack(alignment: .leading){
										HStack{
											if channel.name?.isEmpty ?? false {
												if channel.role == 1 {
													Text(String("PrimaryChannel").camelCaseToWords())
												} else {
													Text(String("Channel \(channel.index)").camelCaseToWords())
												}
											} else {
												Text(String(channel.name ?? "Channel \(channel.index)").camelCaseToWords())
											}
											
											Spacer()
											
											if channel.allPrivateMessages.count > 0 {

												if lastMessageDay == currentDay {
													Text(lastMessageTime, style: .time )
														.font(.system(size: 16))
														.foregroundColor(.secondary)
												} else if  lastMessageDay == (currentDay - 1) {
													Text("Yesterday")
														.font(.system(size: 16))
														.foregroundColor(.secondary)
												} else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
													Text(lastMessageTime.formattedDate(format: dateFormatString))
														.font(.system(size: 16))
														.foregroundColor(.secondary)
												} else if lastMessageDay < (currentDay - 1800) {
													Text(lastMessageTime.formattedDate(format: dateFormatString))
														.font(.system(size: 16))
														.foregroundColor(.secondary)
												}
											}
											
//											Image(systemName: "chevron.forward")
//												.font(.caption)
//												.foregroundColor(.secondary)
										}
										
										if channel.allPrivateMessages.count > 0 {
											HStack(alignment: .top) {
												Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
													.font(.system(size: 16))
													.foregroundColor(.secondary)
											}
										}
									}
								}
								.frame(height: 62)
								.contextMenu {
									Button {
										channel.mute = !channel.mute

										do {
											try context.save()
											// Would rather not do this but the merge changes on
											// A single object is only working on mac GVH
											context.refreshAllObjects()
											// context.refresh(channel, mergeChanges: true)
										} catch {
											context.rollback()
											print("💥 Save Channel Mute Error")
										}
									} label: {
										Label(channel.mute ? "Show Alerts" : "Hide Alerts", systemImage: channel.mute ? "bell" : "bell.slash")
									}

									if channel.allPrivateMessages.count > 0 {
										Button(role: .destructive) {
											isPresentingDeleteChannelMessagesConfirm = true
											channelSelection = channel
										} label: {
											Label("Delete Messages", systemImage: "trash")
										}
									}
								}
								.confirmationDialog(
									"This conversation will be deleted.",
									isPresented: $isPresentingDeleteChannelMessagesConfirm,
									titleVisibility: .visible
								) {
									Button(role: .destructive) {
										deleteChannelMessages(channel: channelSelection!, context: context)
										context.refresh(node!.myInfo!, mergeChanges: true)
										channelSelection = nil
									} label: {
										Text("delete")
									}
								}
							}
						}
						.padding([.top, .bottom])
					}
				}
				Section(header: Text("direct.messages")) {
					ForEach(users) { (user: UserEntity) in
						
						let mostRecent = user.messageList.last
						let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
						let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
						let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
						if  user.num != bleManager.connectedPeripheral?.num ?? 0 {
							
							NavigationLink(destination: UserMessageList(user: user)) {
								ZStack {
									Image(systemName: "circle.fill")
										.opacity(user.unreadMessages > 0 ? 1 : 0)
										.font(.system(size: 10))
										.foregroundColor(.accentColor)
										.brightness(0.2)
								}
								
								CircleText(text: user.shortName ?? "???", color: Color(UIColor(hex: UInt32(user.num))), circleSize: 45, fontSize: (user.shortName ?? "???").isEmoji() ? 32 : (user.shortName?.count ?? 0 == 4  ? 14 : (user.shortName?.count ?? 0 == 3  ? 18 : 22)), brightness: 0.0, textColor: UIColor(hex: UInt32(user.num)).isLight() ? .black : .white)
									.brightness(0.2)
								
								VStack(alignment: .leading){
									HStack{
										Text(user.longName ?? "unknown".localized)
										
										Spacer()
										
										if user.messageList.count > 0 {
											if lastMessageDay == currentDay {
												Text(lastMessageTime, style: .time )
													.font(.system(size: 16))
													.foregroundColor(.secondary)
											} else if lastMessageDay == (currentDay - 1) {
												Text("Yesterday")
													.font(.system(size: 16))
													.foregroundColor(.secondary)
											} else if lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
												Text(lastMessageTime.formattedDate(format: dateFormatString))
													.font(.system(size: 16))
													.foregroundColor(.secondary)
											} else if lastMessageDay < (currentDay - 1800) {
												Text(lastMessageTime.formattedDate(format: dateFormatString))
													.font(.system(size: 16))
													.foregroundColor(.secondary)
											}
										}
										
//										Image(systemName: "chevron.forward")
//											.font(.caption)
//											.foregroundColor(.secondary)
									}
									
									if user.messageList.count > 0 {
										HStack(alignment: .top) {
											Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
												.font(.system(size: 16))
												.foregroundColor(.secondary)
										}
									}
								}
							}
							.frame(height: 62)
							.contextMenu {
								Button {
									user.mute = !user.mute
									do {
										try context.save()
									} catch {
										context.rollback()
										print("💥 Save User Mute Error")
									}
								} label: {
									Label(user.mute ? "Show Alerts" : "Hide Alerts", systemImage: user.mute ? "bell" : "bell.slash")
								}
								Button {
									let success = bleManager.sendTraceRouteRequest(destNum: user.num, wantResponse: true)
									if success {
										isPresentingTraceRouteSentAlert = true
									}
								} label: {
									Label("Trace Route", systemImage: "signpost.right.and.left")
								}
								if user.messageList.count  > 0 {
									Button(role: .destructive) {
										isPresentingDeleteUserMessagesConfirm = true
										userSelection = user
									} label: {
										Label("Delete Messages", systemImage: "trash")
									}
								}
							}
							.alert(
								"Trace Route Sent",
								isPresented: $isPresentingTraceRouteSentAlert
							) {
								Button("OK", role: .cancel) { }
							}
							message: {
								Text("This could take a while, response will appear in the mesh log.")
							}
							.confirmationDialog(
								"This conversation will be deleted.",
								isPresented: $isPresentingDeleteUserMessagesConfirm,
								titleVisibility: .visible
							) {
								Button(role: .destructive) {
									deleteUserMessages(user: userSelection!, context: context)
									context.refresh(node!.user!, mergeChanges: true)
								} label: {
									Text("delete")
								}
							}
						}
					}
				}
			}
			.listStyle(.grouped)
			.navigationTitle("contacts")
			.navigationBarItems(leading:
				MeshtasticLogo()
			)
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
		} detail: {
			if let user = userSelection {
				UserMessageList(user: user)

			} else {
				Text("select.contact")
			}
		}
    }
}
