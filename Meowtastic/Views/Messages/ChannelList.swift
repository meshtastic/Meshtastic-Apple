import SwiftUI
import CoreData
import OSLog

struct ChannelList: View {
	var restrictedChannels = ["gpio", "mqtt", "serial"]

	@StateObject
	var appState = AppState.shared
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager

	@State
	var node: NodeInfoEntity?

	private let dateFormatString = DateFormatter.dateFormat(
		fromTemplate: "yyMMdd",
		options: 0,
		locale: Locale.current
	) ?? "MM/dd/YY"

	@State
	private var channelSelection: ChannelEntity? // Nothing selected by default.
	@State
	private var isPresentingDeleteChannelMessagesConfirm: Bool = false
	@State
	private var isPresentingTraceRouteSentAlert = false

	var body: some View {
		VStack {
			if
				let node,
				let myInfo = node.myInfo,
				let channels = myInfo.channels?.array as? [ChannelEntity]
			{
				List(channels, id: \.self) { channel in
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
										let adminMessageId =  bleManager.saveChannel(
											channel: channel.protoBuf,
											fromUser: node.user!,
											toUser: node.user!
										)
										
										if adminMessageId > 0 {
											context.refresh(channel, mergeChanges: true)
										}

										try context.save()
									} catch {
										context.rollback()
										Logger.data.error("💥 Save Channel Mute Error")
									}
								} label: {
									Label(
										channel.mute ? "Show Alerts" : "Hide Alerts",
										systemImage: channel.mute ? "bell" : "bell.slash"
									)
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

									let badge = appState.unreadChannelMessages + appState.unreadDirectMessages
									UNUserNotificationCenter.current().setBadgeCount(badge)

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
		.navigationTitle("Channels")
		.navigationBarTitleDisplayMode(.large)
		.navigationBarItems(
			leading: MeshtasticLogo(),
			trailing: ConnectedDevice(ble: bleManager)
		)
	}

	@ViewBuilder
	private func makeNavigationLink(
		myInfo: MyInfoEntity,
		channel: ChannelEntity
	) -> some View {
		NavigationLink(
			destination: ChannelMessageList(myInfo: myInfo, channel: channel)
		) {
			let mostRecent = channel.allPrivateMessages.last(where: {
				$0.channel == channel.index
			})
			let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
			let lastMessageTime = Date(
				timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0)))
			)
			let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0

			channelIcon(channel: channel)

			VStack(alignment: .leading) {
				HStack {
					if let name = channel.name, !name.isEmpty {
						Text(String(name).camelCaseToWords())
							.font(.headline)
					}
					else {
						if channel.role == 1 {
							Text("Primary Channel")
								.font(.headline)
						}
						else {
							Text("Channel #\(channel.index)")
								.font(.headline)
						}
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
							.font(.footnote)
							.foregroundColor(.secondary)
					}
				}
			}
		}
	}

	@ViewBuilder
	private func channelIcon(channel: ChannelEntity) -> some View {
		ZStack(alignment: .top) {
			Avatar(
				String(channel.index),
				background: .accentColor,
				size: 64
			)
			.padding(.all, 4)

			if channel.unreadMessages > 0 {
				HStack(spacing: 0) {
					Spacer()

					Image(systemName: "circle.fill")
						.font(.system(size: 16))
						.foregroundColor(.red)
				}
			}
		}
		.frame(width: 72, height: 72)
	}
}
