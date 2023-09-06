//
//  ChannelList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData

struct ChannelList: View {
	
	@StateObject var appState = AppState.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State var node: NodeInfoEntity?

	@State private var channelSelection: ChannelEntity? // Nothing selected by default.
	@State private var isPresentingDeleteChannelMessagesConfirm: Bool = false

	@State private var isPresentingTraceRouteSentAlert = false
	
	var body: some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")
		
		NavigationStack {
			
			List {
				// Display Contacts for the rest of the non admin channels
				if node != nil && node!.myInfo != nil && node!.myInfo!.channels != nil {
					ForEach(node!.myInfo!.channels!.array as! [ChannelEntity], id: \.self) { (channel: ChannelEntity) in
						if channel.name?.lowercased() ?? "" != "admin" && channel.name?.lowercased() ?? "" != "gpio" && channel.name?.lowercased() ?? "" != "serial" {

							NavigationLink(destination: ChannelMessageList(myInfo: node!.myInfo!, channel: channel)) {

								let mostRecent = channel.allPrivateMessages.last(where: { $0.channel == channel.index })
								let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
								let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
								let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0

								
								ZStack {
									Image(systemName: "circle.fill")
										.opacity(channel.unreadMessages > 0 ? 1 : 0)
										.font(.system(size: 10))
										.foregroundColor(.accentColor)
										.brightness(0.2)
								}
								CircleText(text: String(channel.index), color: .accentColor)
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
//										Image(systemName: "chevron.forward")
//											.font(.caption)
//											.foregroundColor(.secondary)
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
									UIApplication.shared.applicationIconBadgeNumber = appState.unreadChannelMessages + appState.unreadDirectMessages
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
			.listStyle(.plain)
			.navigationTitle("channels")
		}
	}
}
