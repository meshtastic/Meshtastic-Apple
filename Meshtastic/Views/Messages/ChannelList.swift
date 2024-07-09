//
//  ChannelList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData
import OSLog

struct ChannelList: View {

	@StateObject var appState = AppState.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State var node: NodeInfoEntity?

	@State private var channelSelection: ChannelEntity? // Nothing selected by default.
	@State private var isPresentingDeleteChannelMessagesConfirm: Bool = false

	@State private var isPresentingTraceRouteSentAlert = false

	var restrictedChannels = ["gpio", "mqtt", "serial"]

	@ViewBuilder
	private func makeNavigationLink(
		myInfo: MyInfoEntity,
		channel: ChannelEntity
	) -> some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")

		NavigationLink(destination: ChannelMessageList(myInfo: myInfo, channel: channel)) {
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

			VStack(alignment: .leading) {
				HStack {
					if channel.name?.isEmpty ?? false {
						if channel.role == 1 {
							Text(String("PrimaryChannel").camelCaseToWords())
								.font(.headline)
						} else {
							Text(String("Channel \(channel.index)").camelCaseToWords())
								.font(.headline)
						}
					} else {
						Text(String(channel.name ?? "Channel \(channel.index)").camelCaseToWords())
							.font(.headline)
					}

					Spacer()

					if channel.allPrivateMessages.count > 0 {

						if lastMessageDay == currentDay {
							Text(lastMessageTime, style: .time )
								.font(.footnote)
								.foregroundColor(.secondary)
						} else if  lastMessageDay == (currentDay - 1) {
							Text("Yesterday")
								.font(.footnote)
								.foregroundColor(.secondary)
						} else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
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

				if channel.allPrivateMessages.count > 0 {
					HStack(alignment: .top) {
						Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
							// .font(.system(size: 16))
							.font(.footnote)
							.foregroundColor(.secondary)
					}
				}
			}
		}
	}
	var body: some View {
		VStack {
			// Display Contacts for the rest of the non admin channels
			if let node, let myInfo = node.myInfo, let channels = myInfo.channels?.array as? [ChannelEntity] {
				List(channels, id: \.self) { (channel: ChannelEntity) in
					if !restrictedChannels.contains(channel.name?.lowercased() ?? "") {
						makeNavigationLink(myInfo: myInfo, channel: channel)
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
								Button {
									channel.mute = !channel.mute

									do {
										let adminMessageId =  bleManager.saveChannel(channel: channel.protoBuf, fromUser: node.user!, toUser: node.user!)
										if adminMessageId > 0 {
											context.refresh(channel, mergeChanges: true)
										}

										try context.save()

									} catch {
										context.rollback()
										Logger.data.error("💥 Save Channel Mute Error")
									}
								} label: {
									Label(channel.mute ? "Show Alerts" : "Hide Alerts", systemImage: channel.mute ? "bell" : "bell.slash")
								}
							}
							.confirmationDialog(
								"This conversation will be deleted.",
								isPresented: $isPresentingDeleteChannelMessagesConfirm,
								titleVisibility: .visible
							) {
								Button(role: .destructive) {
									deleteChannelMessages(channel: channelSelection!, context: context)
									context.refresh(myInfo, mergeChanges: true)
									UIApplication.shared.applicationIconBadgeNumber = appState.unreadChannelMessages + appState.unreadDirectMessages
									channelSelection = nil
								} label: {
									Text("delete")
								}
							}
							.onAppear {
								if self.bleManager.context == nil {
									self.bleManager.context = context
								}
							}
					}
				}
				.padding([.top, .bottom])
				.listStyle(.plain)
			}
		}
		.navigationTitle("channels")
	}
}
