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

			List(users) { (user: UserEntity) in

				if user.receivedMessages?.count ?? 0 > 0 {
					
					let currentUserNum = self.bleManager.connectedPeripheral != nil ? self.bleManager.connectedPeripheral.num : 0

					let mostRecentBC = user.receivedMessages?.array.last as! MessageEntity
					
					let mostRecentDM = user.receivedMessages?.array.last(where: {($0 as! MessageEntity).toUser!.num == currentUserNum }) as? MessageEntity
					
					let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64(mostRecentDM?.messageTimestamp ?? mostRecentBC.messageTimestamp)))
					let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
					let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0

					if user.num == bleManager.broadcastNodeNum {//user.num != currentUserNum && (user.num == bleManager.broadcastNodeNum || mostRecentDM != nil) {
						
							NavigationLink(destination: UserMessageList(user: user)
											.environment(\.managedObjectContext, self.context)) {

							HStack {

								VStack {

									CircleText(text: user.shortName ?? "???", color: Color.blue)
								}
								.padding([.leading, .trailing])

								VStack {

									HStack {

										VStack {

											Text(user.longName ?? "Unknown").font(.headline).fixedSize()
										}

										VStack {

											if lastMessageDay == currentDay {

												Text(lastMessageTime, style: .time )
													.font(.caption)
													.foregroundColor(.gray)

											} else if  lastMessageDay == (currentDay - 1) {

												Text("Yesterday")
													.font(.callout)
													.foregroundColor(.gray)

											} else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {

												Text(lastMessageTime, style: .date)

											} else {

												Text(lastMessageTime, style: .date)
											}
										}.frame(maxWidth: .infinity, alignment: .trailing)
									}
									.listRowSeparator(.hidden).frame(height: 5)

									HStack(alignment: .top) {
										Text(mostRecentDM != nil ? mostRecentDM?.messagePayload as! String : (mostRecentBC.messagePayload ?? "Unknown" ))
											.frame(height: 60)
											.truncationMode(.tail)
											.foregroundColor(Color.gray)
											.frame(maxWidth: .infinity, alignment: .leading)
									}
								}.padding(.top, 15)
							}
						}
					}
					
				} else if false {// self.bleManager.connectedPeripheral == nil || ((self.bleManager.connectedPeripheral != nil ? self.bleManager.connectedPeripheral.num : 0) != user.num) {

					NavigationLink(destination: UserMessageList(user: user)) {

						HStack {

							VStack {

								CircleText(text: user.shortName ?? "???", color: Color.blue)
							}
							.padding(.trailing)

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
								.listRowSeparator(.hidden).frame(height: 5)
							}
						}.padding()
					}
				}
			}
			.navigationTitle("Contacts")
			.navigationBarTitleDisplayMode(.inline)
		}
		.listStyle(PlainListStyle())
    }
}

struct Contacts_Previews: PreviewProvider {
    static var previews: some View {
        Contacts()
    }
}
