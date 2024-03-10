//
//  UserList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData
#if canImport(TipKit)
import TipKit
#endif

struct UserList: View {
	
	@StateObject var appState = AppState.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var searchText = ""
	
	var usersQuery: Binding<String> {
		 Binding {
			 searchText
		 } set: { newValue in
			 searchText = newValue
			 /// Case Insensitive Search Text Predicates
			 let searchPredicates = ["userId", "hwModel", "longName", "shortName"].map { property in
				 return NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
			 }
			 /// Create a compound predicate using each text search predicate as an OR
			 let textSearchPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
			 users.nsPredicate = newValue.isEmpty ? nil : textSearchPredicate
		 }
	}
	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "lastMessage", ascending: false), NSSortDescriptor(key: "vip", ascending: false), NSSortDescriptor(key: "longName", ascending: true)],
		animation: .default)

	private var users: FetchedResults<UserEntity>
	@State var node: NodeInfoEntity?
	@State private var userSelection: UserEntity? // Nothing selected by default.
	@State private var isPresentingDeleteUserMessagesConfirm: Bool = false
	
	var body: some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")
		VStack {
			List {
				if #available(iOS 17.0, macOS 14.0, *) {
					TipView(ContactsTip(), arrowEdge: .bottom)
				}
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
							
							CircleText(text: user.shortName ?? "?", color: Color(UIColor(hex: UInt32(user.num))))
							
							VStack(alignment: .leading){
								HStack{
									Text(user.longName ?? "unknown".localized)
										.font(.headline)
									Spacer()
									if user.vip {
										Image(systemName: "star.fill")
											.foregroundColor(.yellow)
									}
									if user.messageList.count > 0 {
										if lastMessageDay == currentDay {
											Text(lastMessageTime, style: .time )
												.font(.footnote)
												.foregroundColor(.secondary)
										} else if lastMessageDay == (currentDay - 1) {
											Text("Yesterday")
												.font(.footnote)
												.foregroundColor(.secondary)
										} else if lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
											Text(lastMessageTime.formattedDate(format: dateFormatString))
												.font(.footnote)
												.foregroundColor(.secondary)
										} else if lastMessageDay < (currentDay - 1800) {
											Text(lastMessageTime.formattedDate(format: dateFormatString))
												.font(.footnote)
												.foregroundColor(.secondary)
										}
									}
								}
								
								if user.messageList.count > 0 {
									HStack(alignment: .top) {
										Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
											.font(.footnote)
											.foregroundColor(.secondary)
									}
								}
							}
						}
						.frame(height: 62)
						.contextMenu {
							Button {
								user.vip = !user.vip
								do {
									try context.save()
								} catch {
									context.rollback()
									print("💥 Save User VIP Error")
								}
							} label: {
								Label(user.vip ? "Un-Favorite" : "Favorite", systemImage: user.vip ? "star.slash.fill" : "star.fill")
							}
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
							if user.messageList.count  > 0 {
								Button(role: .destructive) {
									isPresentingDeleteUserMessagesConfirm = true
									userSelection = user
								} label: {
									Label("Delete Messages", systemImage: "trash")
								}
							}
						}
						.confirmationDialog(
							"This conversation will be deleted.",
							isPresented: $isPresentingDeleteUserMessagesConfirm,
							titleVisibility: .visible
						) {
							Button(role: .destructive) {
								deleteUserMessages(user: userSelection!, context: context)
								context.refresh(node!.user!, mergeChanges: true)
								UIApplication.shared.applicationIconBadgeNumber = appState.unreadChannelMessages + appState.unreadDirectMessages
							} label: {
								Text("delete")
							}
						}
					}
				}
			}
			.listStyle(.plain)
			.navigationTitle(String.localizedStringWithFormat("contacts %@".localized, String(users.count == 0 ? 0 : users.count - 1)))
			.searchable(text: usersQuery, placement: users.count > 10 ? .navigationBarDrawer(displayMode: .always) : .automatic, prompt: "Find a contact")
			.disableAutocorrection(true)
		}
	}
}
