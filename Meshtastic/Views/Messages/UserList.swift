//
//  UserList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData

struct UserList: View {
	
	@State private var searchText = ""
	var usersQuery: Binding<String> {
		 Binding {
			 searchText
		 } set: { newValue in
			 searchText = newValue
			 users.nsPredicate = newValue.isEmpty ? nil : NSPredicate(format: "longName CONTAINS[c] %@ OR shortName CONTAINS[c] %@", newValue, newValue)
		 }
	 }
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "lastMessage", ascending: false), NSSortDescriptor(key: "longName", ascending: true)],
		animation: .default)

	private var users: FetchedResults<UserEntity>
	@State var node: NodeInfoEntity?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var isPresentingDeleteUserMessagesConfirm: Bool = false
	@State private var isPresentingTraceRouteSentAlert = false
	
	var body: some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")
		
		NavigationStack {
			List {
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
							
							CircleText(text: user.shortName ?? "???", color: Color(UIColor(hex: UInt32(user.num))), textColor: UIColor(hex: UInt32(user.num)).isLight() ? .black : .white)
							
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
									//								Image(systemName: "chevron.forward")
									//									.font(.caption)
									//									.foregroundColor(.secondary)
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
			.listStyle(.plain)
			.navigationTitle(String.localizedStringWithFormat("contacts %@".localized, String(users.count)))
			.searchable(text: usersQuery, prompt: "Find a contact")
		}
	}
}
