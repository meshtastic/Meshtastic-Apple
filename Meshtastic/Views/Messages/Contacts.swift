//
//  Contacts.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 12/21/21.
//

import SwiftUI

struct Contacts: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@ObservedObject private var userSettings: UserSettings = UserSettings()
	
	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "longName", ascending: true)],
		animation: .default)
	
	private var users: FetchedResults<UserEntity>

	
	
	private var prefferedNode: NodeInfoEntity?

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "num", ascending: true)],
		animation: .default)

	private var nodes: FetchedResults<NodeInfoEntity>
	
	
	@State private var selection: UserEntity? = nil // Nothing selected by default.

    var body: some View {

		NavigationSplitView {
			List {
				Section(header: Text("Direct Messages")) {
					ForEach(users) { (user: UserEntity) in
						
						if  user.num != bleManager.userSettings?.preferredNodeNum ?? 0 {
							
							NavigationLink(destination: MessageList(user: user)) {
								
								if user.messageList.count > 0 {
									
									let mostRecent = user.num == bleManager.broadcastNodeNum ? user.messageList.last : user.messageList.last(where: { $0.toUser?.num ?? 0 !=  bleManager.broadcastNodeNum })
									let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
									let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
									let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
									
									HStack {
										VStack(alignment: .leading) {
											HStack {
												CircleText(text: user.shortName ?? "???", color: Color.blue, circleSize: 52, fontSize: 16)
												.padding(.trailing, 5)
												VStack {
													Text(user.longName ?? "Unknown").font(.headline)
												}
												.frame(maxWidth: .infinity, alignment: .leading)
												
												VStack (alignment: .trailing) {
													if lastMessageDay == currentDay {
														Text(lastMessageTime, style: .time )
															.font(.callout)
															.foregroundColor(.gray)
													} else if  lastMessageDay == (currentDay - 1) {
														Text("Yesterday")
															.font(.callout)
															.foregroundColor(.gray)
													} else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
														Text(lastMessageTime.formattedDate(format: "MM/dd/yy"))
															.font(.callout)
															.foregroundColor(.gray)
													} else if lastMessageDay < (currentDay - 1800) {
														Text(lastMessageTime.formattedDate(format: "MM/dd/yy"))
															.font(.callout)
															.foregroundColor(.gray)
													}
												}
											}
											HStack(alignment: .top) {
												Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
													.truncationMode(.tail)
													.foregroundColor(Color.gray)
													.frame(maxWidth: .infinity, alignment: .leading)
											}
										}
									}
								} else {
									HStack {
										VStack(alignment: .leading) {
											CircleText(text: user.shortName ?? "???", color: Color.blue, circleSize: 52, fontSize: 16)
												.padding(.trailing, 5)
										}
										VStack {
											HStack {
												VStack {
													Text(user.longName ?? "Unknown").font(.headline).fixedSize()
												}
												VStack {
													Text("               ")
												}
												.frame(maxWidth: .infinity, alignment: .trailing)
											}
											HStack(alignment: .top) {
												Text(" ")
													.truncationMode(.tail)
													.foregroundColor(Color.gray)
													.frame(maxWidth: .infinity, alignment: .leading)
											}
										}
										.padding(.top)
									}
								}
							}
						}
					}
				}
				Section(header: Text("Private Channels")) {
					// Display Contacts for the rest of the non admin channels
					
				}
			}
			.tint(Color(UIColor.systemGray))
			.navigationSplitViewStyle(.automatic)
			.navigationTitle("Contacts")
			.navigationBarTitleDisplayMode(.inline)
			.navigationBarItems(leading:
				MeshtasticLogo()
			)
		}
		detail: {
		
			if let user = selection {
				
				MessageList(user:user)
				
			} else {
				
				Text("Select a user")
			}
		}

    }
}
