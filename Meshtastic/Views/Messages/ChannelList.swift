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

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Binding var node: NodeInfoEntity?
	@Binding var channelSelection: ChannelEntity?
	@State private var channelToDeleteMessages: ChannelEntity?
	@State private var isPresentingDeleteChannelMessagesConfirm: Bool = false
	@State private var isPresentingTraceRouteSentAlert = false
	@State private var showingHelp = false

	var restrictedChannels = ["gpio", "mqtt", "serial", "admin"]

	@FetchRequest(
			sortDescriptors: [NSSortDescriptor(keyPath: \ChannelEntity.index, ascending: true)],
			predicate: nil,
			animation: .default
		) private var channels: FetchedResults<ChannelEntity>

	@ViewBuilder
	private func makeChannelRow(
		myInfo: MyInfoEntity,
		channel: ChannelEntity
	) -> some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")

		NavigationLink(value: channel) {
			let mostRecent = channel.mostRecentPrivateMessage
			let hasMessages = mostRecent != nil
			let hasUnreadMessages = hasMessages && (channel.unreadMessages > 0)
			let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
			let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
			let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0

			ZStack {
				Image(systemName: "circle.fill")
					.opacity(hasUnreadMessages ? 1 : 0)
					.font(.system(size: 10))
					.foregroundColor(.accentColor)
					.brightness(0.2)
			}
			CircleText(text: String(channel.index), color: .accentColor)
				.brightness(0.2)

			VStack(alignment: .leading) {
				HStack {
					ChannelLock(channel: channel)
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

					if hasMessages {

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
					if channel.mute {
						Image(systemName: "bell.slash")
					}
				}

				if hasMessages {
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
			if let node, let myInfo = node.myInfo {
				List(selection: $channelSelection) {
					ForEach(channels) { (channel: ChannelEntity) in
						let hasMessages = channel.mostRecentPrivateMessage != nil
						if !restrictedChannels.contains(channel.name?.lowercased() ?? "") {
							makeChannelRow(myInfo: myInfo, channel: channel)
								.alignmentGuide(.listRowSeparatorLeading) {
									$0[.leading]
								}
								.frame(height: 62)
								.contextMenu {
									if hasMessages {
										Button(role: .destructive) {
											isPresentingDeleteChannelMessagesConfirm = true
											channelToDeleteMessages = channel
										} label: {
											Label("Delete Messages", systemImage: "trash")
										}
									}
									Button {
										channel.mute.toggle()
										do {
											Task {
												do {
													_ = try await accessoryManager.saveChannel(channel: channel.protoBuf, fromUser: node.user!, toUser: node.user!)
													Task { @MainActor in
														do {
															context.refresh(channel, mergeChanges: true)
															try context.save()
														} catch {
															context.rollback()
															Logger.data.error("💥 Save Channel Mute Error")
														}
													}
												} catch {
													Logger.mesh.error("Unable to save channel")
												}
											}
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
										Task {
											await MeshPackets.shared.deleteChannelMessages(channel: channelToDeleteMessages!)
											context.refresh(myInfo, mergeChanges: true)
											channelToDeleteMessages = nil
										}
									} label: {
										Text("Delete")
									}
								}
						}
					}
				}
				.olderThanOS26 { $0.padding([.top, .bottom]) }
				.listStyle(.plain)
			}
		}
		.sheet(isPresented: $showingHelp) {
			ChannelsHelp()
				.presentationDetents([.large])
				.presentationDragIndicator(.visible)
		}
		.safeAreaInset(edge: .bottom, alignment: .leading) {
			HStack {
				Button(action: {
					withAnimation {
						showingHelp = !showingHelp
					}
				}) {
					Image(systemName: !showingHelp ? "questionmark.circle" : "questionmark.circle.fill")
						.padding(.vertical, 5)
				}
				.tint(Color(UIColor.secondarySystemBackground))
				.foregroundColor(.accentColor)
				.buttonStyle(.borderedProminent)
			}
			.controlSize(.regular)
			.padding(5)
		}
		.padding(.bottom, 5)
		.navigationTitle("Channels")
	}
}
