//
//  Contacts.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 12/21/21.
//

import SwiftUI

struct Contacts: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "longName", ascending: true)],
		animation: .default)
	
		private var users: FetchedResults<UserEntity>
	
    var body: some View {
		NavigationView {
			List(users) { user in
				
				if user.receivedMessages?.count ?? 0 > 0 {
					
					let mostRecent = user.receivedMessages?.lastObject as! MessageEntity
					let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64(mostRecent.messageTimestamp)))
					let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
					let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
				
					HStack  {
						VStack {
							CircleText(text: user.shortName ?? "???", color: Color.blue)
						}
						VStack {
							
							HStack (alignment: .bottom){

								VStack {
									Text(user.longName ?? "Unknown").font(.headline)
								}
					
								VStack {
									if lastMessageDay == currentDay {
										
										Text(lastMessageTime, style: .time )
											.font(.caption)
											.foregroundColor(.gray)
										
									} else if ( lastMessageDay == (currentDay - 1)) {
										
										Text("Yesterday")
											.font(.callout)
											.foregroundColor(.gray)
										
									} else if ( lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) ) {
										
										Text(lastMessageTime, style: .date)
										
									} else {
										
										Text(lastMessageTime, style: .date)
									}
								}.frame(maxWidth: .infinity, alignment: .trailing)
							}
							.listRowSeparator(.hidden).frame(height: 5)
							HStack (alignment: .top) {
								
								Text(mostRecent.messagePayload ?? "EMPTY MESSSAGE")
									.frame(height: 60)
									.truncationMode(.tail)
							}
						}
					}.padding(10)
				} else {
					HStack  {
						VStack {
							CircleText(text: user.shortName ?? "???", color: Color.blue)
						}
						VStack {
							
							HStack{

								VStack {
									Text(user.longName ?? "Unknown").font(.title3)
								}
							}
						}
					}.padding()
				}
				//NavigationLink(note.title, destination: NoteEditor(id: note.id))
			}
			.navigationTitle("Contacts")
		}
    }
}

struct Contacts_Previews: PreviewProvider {
    static var previews: some View {
        Contacts()
    }
}
