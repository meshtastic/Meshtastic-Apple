//
//  MeshMessagesWidget.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Unread counts and the latest messages. Snippets are privacy sensitive so
//  the lock screen redacts them until the phone is unlocked. The widget has
//  no small family on purpose: no message reading in CarPlay or StandBy —
//  the CarPlay app handles messages properly.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct MeshMessagesEntry: TimelineEntry {
	let date: Date
	let snapshot: WidgetSnapshot?

	/// Staleness is the snapshot's age at the entry's own date — never the
	/// entry's position in a timeline.
	var isStale: Bool {
		guard let snapshot else { return false }
		return date.timeIntervalSince(snapshot.generatedAt) >= 2 * 3600
	}
}

struct MeshMessagesProvider: TimelineProvider {
	func placeholder(in context: Context) -> MeshMessagesEntry {
		MeshMessagesEntry(date: .now, snapshot: .messagesPreview)
	}

	func getSnapshot(in context: Context, completion: @escaping (MeshMessagesEntry) -> Void) {
		let snapshot = context.isPreview ? (WidgetSnapshotStore.load() ?? .messagesPreview) : WidgetSnapshotStore.load()
		completion(MeshMessagesEntry(date: .now, snapshot: snapshot))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<MeshMessagesEntry>) -> Void) {
		let snapshot = WidgetSnapshotStore.load()
		let now = Date()
		// The stale flip belongs two hours after the snapshot was generated, not
		// two hours after this reload. Once that moment has passed (or there is
		// no snapshot) the tail entry only sets the .atEnd reload cadence.
		var secondDate = now.addingTimeInterval(2 * 3600)
		if let generatedAt = snapshot?.generatedAt {
			let staleDate = generatedAt.addingTimeInterval(2 * 3600)
			if staleDate > now {
				secondDate = staleDate
			}
		}
		let entries = [
			MeshMessagesEntry(date: now, snapshot: snapshot),
			MeshMessagesEntry(date: secondDate, snapshot: snapshot)
		]
		completion(Timeline(entries: entries, policy: .atEnd))
	}
}

// MARK: - Widget

struct MeshMessagesWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "MeshMessages", provider: MeshMessagesProvider()) { entry in
			MeshMessagesWidgetView(entry: entry)
				.containerBackground(Color(UIColor.systemBackground), for: .widget)
		}
		.configurationDisplayName("Messages")
		.description("Unread counts and your latest mesh messages.")
		.supportedFamilies([
			.systemMedium, .systemLarge,
			.accessoryInline, .accessoryRectangular
		])
	}
}

// MARK: - Views

struct MeshMessagesWidgetView: View {
	@Environment(\.widgetFamily) private var family
	let entry: MeshMessagesEntry

	var body: some View {
		if let snapshot = entry.snapshot {
			content(snapshot)
				.opacity(entry.isStale ? 0.55 : 1)
		} else {
			noDataView
		}
	}

	@ViewBuilder
	private func content(_ snapshot: WidgetSnapshot) -> some View {
		switch family {
		case .accessoryInline:
			MessagesInlineView(snapshot: snapshot)
		case .accessoryRectangular:
			MessagesRectangularView(snapshot: snapshot)
		case .systemLarge:
			MessagesListView(snapshot: snapshot, rowLimit: 5)
		default:
			MessagesListView(snapshot: snapshot, rowLimit: 2)
		}
	}

	@ViewBuilder
	private var noDataView: some View {
		switch family {
		case .accessoryInline:
			Text("Open Meshtastic")
		default:
			VStack(spacing: 6) {
				Image(systemName: "message")
					.font(.title2)
					.foregroundStyle(.secondary)
					.widgetAccentable()
				Text("Open Meshtastic to load messages")
					.font(.caption2)
					.multilineTextAlignment(.center)
					.foregroundStyle(.secondary)
			}
		}
	}
}

// MARK: System families

private struct MessagesListView: View {
	let snapshot: WidgetSnapshot
	let rowLimit: Int

	var body: some View {
		VStack(alignment: .leading, spacing: 7) {
			HStack(spacing: 5) {
				MeshLogo(height: 10)
				Text("Messages")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.textCase(.uppercase)
				Spacer()
				let total = snapshot.unreadChannelMessages + snapshot.unreadDirectMessages
				if total > 0 {
					Text("\(total) unread")
						.font(.caption.weight(.semibold))
						.foregroundStyle(Color.accentColor)
						.widgetAccentable()
				}
			}
			if snapshot.recentMessages.isEmpty {
				Spacer()
				Text("No messages yet")
					.font(.caption)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .center)
				Spacer()
			} else {
				ForEach(snapshot.recentMessages.prefix(rowLimit)) { message in
					Link(destination: deepLink(for: message)) {
						MessageRow(message: message)
					}
				}
				Spacer(minLength: 0)
			}
		}
	}
}

/// One conversation row, shaped like a mail inbox row: unread dot in a fixed
/// leading gutter, avatar circle, sender and time on the first line, the
/// message underneath.
private struct MessageRow: View {
	let message: MessageSnapshot

	var body: some View {
		HStack(alignment: .top, spacing: 7) {
			Circle()
				.fill(Color.accentColor)
				.frame(width: 7, height: 7)
				.opacity(message.isUnread ? 1 : 0)
				.padding(.top, 6)
				.widgetAccentable()
			NodeChip(shortName: message.senderShortName, colorSeed: message.senderColorSeed, size: 27)
			VStack(alignment: .leading, spacing: 1) {
				HStack(alignment: .firstTextBaseline, spacing: 5) {
					Text(message.senderLongName)
						.font(.subheadline.weight(.semibold))
						.lineLimit(1)
						.layoutPriority(1)
					if case .channel(_, let name) = message.kind, !name.isEmpty {
						Text(name)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					Spacer(minLength: 6)
					Text(message.timestamp, style: .relative)
						.font(.caption2)
						.foregroundStyle(.tertiary)
				}
				Text(message.text)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2, reservesSpace: false)
					.multilineTextAlignment(.leading)
					.privacySensitive()
			}
		}
	}
}

// MARK: Accessory families

private struct MessagesInlineView: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		let total = snapshot.unreadChannelMessages + snapshot.unreadDirectMessages
		if total > 0 {
			Text("\(Image(systemName: "message.fill")) \(total) unread")
		} else {
			Text("\(Image(systemName: "message")) No unread")
		}
	}
}

private struct MessagesRectangularView: View {
	let snapshot: WidgetSnapshot

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			HStack(spacing: 4) {
				MeshLogo(height: 9)
				Text("Messages")
					.font(.headline)
				Spacer()
				let total = snapshot.unreadChannelMessages + snapshot.unreadDirectMessages
				if total > 0 {
					Text("\(total)")
						.font(.headline)
				}
			}
			.widgetAccentable()
			if let latest = snapshot.recentMessages.first {
				Text(latest.senderLongName)
					.font(.caption.weight(.semibold))
					.lineLimit(1)
				Text(latest.text)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.privacySensitive()
			} else {
				Text("No messages yet")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		// A tap opens the conversation of the message shown, like the system widget's rows.
		.widgetURL(snapshot.recentMessages.first.map(deepLink(for:)))
	}
}

// MARK: Helpers

private func deepLink(for message: MessageSnapshot) -> URL {
	let path: String
	switch message.kind {
	case .channel(let index, _):
		path = "meshtastic:///messages?channelId=\(index)&messageId=\(message.messageId)"
	case .directMessage(let userNum):
		path = "meshtastic:///messages?userNum=\(userNum)&messageId=\(message.messageId)"
	}
	return URL(string: path) ?? URL(string: "meshtastic:///messages")!
}

// MARK: Preview data

extension WidgetSnapshot {
	/// Gallery and placeholder content — never written to the store.
	static var messagesPreview: WidgetSnapshot {
		WidgetSnapshot(
			generatedAt: Date(timeIntervalSinceNow: -120),
			connectionState: .connected,
			radioNodeNum: 0x67EA94,
			radioLongName: "Meshtastic 5fac",
			radioShortName: "5fac",
			radioBatteryLevel: 87,
			localStats: nil,
			nodes: [],
			totalNodeCount: 87,
			unreadChannelMessages: 2,
			unreadDirectMessages: 1,
			recentMessages: [
				MessageSnapshot(
					messageId: 1,
					kind: .channel(index: 0, name: "Primary"),
					senderShortName: "BCS1",
					senderLongName: "Basecamp Solar",
					senderColorSeed: 0x43B2A1,
					text: "Anyone near the ridge repeater today?",
					timestamp: Date(timeIntervalSinceNow: -540),
					isUnread: true
				),
				MessageSnapshot(
					messageId: 2,
					kind: .directMessage(userNum: 0x1A2B3C),
					senderShortName: "WX2",
					senderLongName: "Weather Station 2",
					senderColorSeed: 0x1A2B3C,
					text: "Wind picking up at the summit.",
					timestamp: Date(timeIntervalSinceNow: -1980),
					isUnread: true
				)
			]
		)
	}
}
