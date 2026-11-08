//
//  ChannelList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import SwiftData
import OSLog

struct ChannelList: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Binding var node: NodeInfoEntity?
	@Binding var channelSelection: ChannelEntity?
	@State private var channelToDeleteMessages: ChannelEntity?
	@State private var isPresentingDeleteChannelMessagesConfirm: Bool = false
	@State private var isPresentingTraceRouteSentAlert = false
	@State private var showingHelp = false
	@State private var archivedConversations: [ChannelConversationRecord] = []

	private var visibleChannels: [ChannelEntity] {
		guard let myInfo = node?.myInfo else { return [] }

		var channelsByIndex: [Int32: ChannelEntity] = [:]
		for channel in myInfo.channels {
			channelsByIndex[channel.index] = channel
		}

		// Module channels (reserved names) carry protocol traffic, not messages.
		// ChannelForm warns when one of these names is entered, since a hidden
		// channel with no explanation reads as data loss (#2275).
		return channelsByIndex
			.values
			.filter { !ChannelEntity.isReservedModuleName($0.name ?? "") }
			.sorted { $0.index < $1.index }
	}

	@ViewBuilder
	private func makeChannelRow(
		myInfo: MyInfoEntity,
		channel: ChannelEntity
	) -> some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")

		let isArchived = channel.index < 0
		NavigationLink(value: channel) {
			let mostRecent = channel.mostRecentPrivateMessage
			let hasMessages = mostRecent != nil
			// `channel.unreadMessages` runs a FetchRequest; fetch once and reuse for both the
			// indicator and its VoiceOver label instead of hitting Core Data twice per row.
			let unreadCount = channel.unreadMessages
			let hasUnreadMessages = hasMessages && (unreadCount > 0)
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
			.accessibilityHidden(!hasUnreadMessages)
			.accessibilityLabel(String(localized: "\(unreadCount) unread", comment: "VoiceOver: number of unread messages in a channel"))
			if isArchived {
				Image(systemName: "archivebox")
					.font(.title2)
					.foregroundColor(.onSurfaceVariant)
					.frame(width: 45, height: 45)
					.accessibilityHidden(true)
			} else {
				CircleText(text: String(channel.index), color: .accentFill)
					.brightness(0.2)
			}

			VStack(alignment: .leading) {
				HStack {
					if !isArchived {
						ChannelLock(channel: channel)
					}
					if channel.name?.isEmpty ?? false {
						if channel.role == 1 {
							Text(String(localized: "Primary Channel"))
								.font(.headline)
						} else {
							Text(String(localized: "Channel \(channel.index)"))
								.font(.headline)
						}
					} else {
						Text(String(channel.name ?? String(localized: "Channel \(channel.index)")))
							.font(.headline)
					}

					Spacer()

					if hasMessages {

						if lastMessageDay == currentDay {
							Text(lastMessageTime, style: .time )
								.font(.footnote)
								.foregroundColor(.onSurfaceVariant)
						} else if  lastMessageDay == (currentDay - 1) {
							Text("Yesterday")
								.font(.footnote)
								.foregroundColor(.onSurfaceVariant)
						} else if  lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
							Text(lastMessageTime.formattedDate(format: dateFormatString))
								.font(.footnote)
								.foregroundColor(.onSurfaceVariant)
						} else if lastMessageDay < (currentDay - 1800) {
							Text(lastMessageTime.formattedDate(format: dateFormatString))
								.font(.footnote)
								.foregroundColor(.onSurfaceVariant)
						}
					}
					if channel.mute {
						Image(systemName: "bell.slash")
							.accessibilityLabel(String(localized: "Muted", comment: "VoiceOver: channel notifications are muted"))
					}
				}

				if isArchived {
					Text("Archived, no longer on the radio")
						.font(.caption)
						.foregroundColor(.onSurfaceVariant)
				}

				if hasMessages {
					HStack(alignment: .top) {
						MessagePreviewText(mostRecent?.messagePayload ?? " ")
							.font(.footnote)
							.foregroundColor(.onSurfaceVariant)
					}
				}
			}
		}
	}
	@ViewBuilder
	private func makeChannelListItem(
		node: NodeInfoEntity,
		myInfo: MyInfoEntity,
		channel: ChannelEntity
	) -> some View {
		let hasMessages = channel.mostRecentPrivateMessage != nil
		makeChannelRow(myInfo: myInfo, channel: channel)
			.alignmentGuide(.listRowSeparatorLeading) {
				$0[.leading]
			}
			.frame(minHeight: 62)
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
					Task {
						do {
							_ = try await accessoryManager.saveChannel(
								channel: channel.protoBuf,
								fromUser: node.user!,
								toUser: node.user!,
								refreshShareSnapshot: true
							)
							Task { @MainActor in
								do {
									try context.save()
								} catch {
									Logger.data.error("💥 Save Channel Mute Error")
								}
							}
						} catch {
							Logger.mesh.error("Unable to save channel")
						}
					}
				} label: {
					Label(channel.mute ? "Show Alerts" : "Hide Alerts", systemImage: channel.mute ? "bell" : "bell.slash")
				}
			}
	}

	/// A conversation whose channel has left the radio. Read only, so the only action is
	/// deleting it.
	@ViewBuilder
	private func makeArchivedListItem(myInfo: MyInfoEntity, record: ChannelConversationRecord) -> some View {
		let channel = ChannelConversations.archivedChannel(for: record)
		makeChannelRow(myInfo: myInfo, channel: channel)
			.alignmentGuide(.listRowSeparatorLeading) {
				$0[.leading]
			}
			.frame(minHeight: 62)
			.contextMenu {
				Button(role: .destructive) {
					isPresentingDeleteChannelMessagesConfirm = true
					channelToDeleteMessages = channel
				} label: {
					Label("Delete Messages", systemImage: "trash")
				}
			}
	}

	var body: some View {
		VStack {
			// Display Contacts for the rest of the non admin channels
			if let node, let myInfo = node.myInfo {
				List(selection: $channelSelection) {
					ForEach(visibleChannels) { (channel: ChannelEntity) in
						makeChannelListItem(node: node, myInfo: myInfo, channel: channel)
					}
					// After every live channel, whatever their slots.
					if !archivedConversations.isEmpty {
						Section("Archived") {
							ForEach(archivedConversations, id: \.key) { record in
								makeArchivedListItem(myInfo: myInfo, record: record)
							}
						}
					}
				}
				.olderThanOS26 { $0.padding([.top, .bottom]) }
				.listStyle(.plain)
				.hostedConfirmation(
					"This conversation will be deleted.",
					isPresented: $isPresentingDeleteChannelMessagesConfirm,
					titleVisibility: .visible
				) {
					Button(role: .destructive) {
						guard let channel = channelToDeleteMessages else { return }
						let key = channel.index
						Task {
							if key < 0 {
								await MeshPackets.shared.deleteArchivedConversation(key: key)
							} else {
								await MeshPackets.shared.deleteChannelMessages(channel: channel)
							}
							await MainActor.run {
								channelToDeleteMessages = nil
								if channelSelection?.index == key && key < 0 { channelSelection = nil }
								archivedConversations = ChannelConversations.archivedConversations(in: context)
							}
						}
					} label: {
						Text("Delete")
					}
				}
			}
			Spacer()
		}
		.task { archivedConversations = ChannelConversations.archivedConversations(in: context) }
		// A reconcile posts this after it moves messages, as do new messages and deletes.
		.onReceive(
			NotificationCenter.default.publisher(for: .meshMessagesDidChange)
				.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
		) { _ in
			archivedConversations = ChannelConversations.archivedConversations(in: context)
		}
		.hostedSheet(isPresented: $showingHelp) {
			ChannelsHelp()
				.trackScreen(.channelsHelp)
				.presentationDetents([.large])
				#if !targetEnvironment(macCatalyst)
				.presentationDragIndicator(.visible)
				#endif
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
				.accessibilityLabel(showingHelp ? String(localized: "Hide help", comment: "VoiceOver label for the help toggle button when help is showing") : String(localized: "Show help", comment: "VoiceOver label for the help toggle button when help is hidden"))
			}
			.controlSize(.regular)
			.padding(5)
		}
		.padding(.bottom, 5)
		.navigationTitle("Channels")
	}
}
