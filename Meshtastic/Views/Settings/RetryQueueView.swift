//
//  RetryQueueView.swift
//  Meshtastic
//
//  Retry queue management view for debugging and queue management
//

import SwiftUI
import MeshtasticProtobufs

struct RetryQueueView: View {
	@State private var queueItems: [RetryQueueItem] = []
	@State private var selectedGroup: RetryGroup?
	@State private var searchText = ""
	@State private var filterType: MessageType?
	@State private var showingDeleteAlert = false
	@State private var itemToDelete: RetryQueueItem?
	@State private var isRefreshing = false
	@State private var refreshTimer: Timer?
	@State private var currentDate = Date()

	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	private var groupedItems: [RetryGroup] {
		let items = filteredItems

		let grouped = Dictionary(grouping: items) { item in
			RetryGroupKey(originalMessageId: item.originalMessageId, messageType: item.messageType)
		}

		return grouped.values.compactMap { items -> RetryGroup? in
			guard let first = items.first else { return nil }
			let sortedItems = items.sorted { $0.createdAt < $1.createdAt }
			return RetryGroup(
				originalMessageId: first.originalMessageId,
				messageType: first.messageType,
				items: sortedItems,
				createdAt: first.createdAt
			)
		}.sorted { $0.createdAt < $1.createdAt }
	}

	private var filteredItems: [RetryQueueItem] {
		var items = queueItems

		if let filter = filterType {
			items = items.filter { $0.messageType == filter }
		}

		if !searchText.isEmpty {
			items = items.filter {
				$0.originalMessageId.description.localizedCaseInsensitiveContains(searchText) ||
				$0.messageType.rawValue.localizedCaseInsensitiveContains(searchText) ||
				($0.currentPacketId?.description.localizedCaseInsensitiveContains(searchText) ?? false)
			}
		}

		return items
	}

	var body: some View {
		VStack(spacing: 0) {
			if idiom == .phone {
				phoneContent
			} else {
				iPadContent
			}
		}
		.searchable(text: $searchText, placement: .navigationBarDrawer, prompt: "Search queue")
		.navigationTitle("Retry Queue\(groupedItems.isEmpty ? "" : " (\(groupedItems.count))")")
		.sheet(item: $selectedGroup) { group in
			RetryQueueDetailSheet(group: group, allItems: groupedItems)
				.presentationDetents([.medium, .large])
				.presentationDragIndicator(.visible)
		}
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Menu {
					Button {
						filterType = nil
					} label: {
						Label("All Types", systemImage: "tray.full")
					}

					Divider()

					ForEach(MessageType.allCases, id: \.self) { type in
						Button {
							filterType = type
						} label: {
							Label(type.rawValue.capitalized, systemImage: type.icon)
						}
					}
				} label: {
					Image(systemName: filterType == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
				}
			}

			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					Task {
						await refreshQueue()
					}
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.disabled(isRefreshing)
			}

			if !groupedItems.isEmpty {
				let hasAnyPending = groupedItems.contains { group in
					group.items.contains { $0.state == .pending || $0.state == .sending || $0.state == .waitingForAck }
				}
				ToolbarItem(placement: .navigationBarTrailing) {
					Menu {
						Button(role: .destructive) {
							itemToDelete = nil
							showingDeleteAlert = true
						} label: {
							Label("Clear All", systemImage: "trash")
						}

						if hasAnyPending {
							Button {
								Task {
									await MessageRetryQueueManager.shared.clearAll()
									await refreshQueue()
								}
							} label: {
								Label("Cancel All Retries", systemImage: "stop.circle")
							}
						}
					} label: {
						Image(systemName: "ellipsis.circle")
					}
				}
			}
		}
		.alert("Delete Item?", isPresented: $showingDeleteAlert) {
			Button("Cancel", role: .cancel) {
				itemToDelete = nil
			}
			Button("Delete", role: .destructive) {
				if let item = itemToDelete {
					Task {
						await MessageRetryQueueManager.shared.cancelRetry(forItemId: item.id)
						await refreshQueue()
					}
				} else {
					Task {
						for group in groupedItems {
							for item in group.items {
								await MessageRetryQueueManager.shared.cancelRetry(forItemId: item.id)
							}
						}
						await refreshQueue()
					}
				}
			}
		} message: {
			if let item = itemToDelete {
				Text("Delete retry for message \(item.originalMessageId.toHex())?")
			} else {
				Text("Delete \(groupedItems.count) group(s) from the queue?")
			}
		}
		.task {
			await refreshQueue()
			startRefreshTimer()
		}
		.onDisappear {
			stopRefreshTimer()
		}
	}

	private func startRefreshTimer() {
		stopRefreshTimer()
		refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
			currentDate = Date()
		}
	}

	private func stopRefreshTimer() {
		refreshTimer?.invalidate()
		refreshTimer = nil
	}

	private func refreshQueue() async {
		isRefreshing = true
		queueItems = await MessageRetryQueueManager.shared.getQueue()
		isRefreshing = false
	}

	@ViewBuilder
	private var phoneContent: some View {
		if groupedItems.isEmpty {
			ContentUnavailableView(
				queueItems.isEmpty ? "Queue Empty" : "No Matching Items",
				systemImage: queueItems.isEmpty ? "checkmark.circle" : "magnifyingglass"
			)
		} else {
			List {
				ForEach(groupedItems) { group in
					RetryGroupRow(group: group, currentDate: currentDate)
						.contentShape(Rectangle())
						.onTapGesture {
							selectedGroup = group
						}
						.swipeActions(edge: .trailing, allowsFullSwipe: true) {
							Button(role: .destructive) {
								itemToDelete = group.items.first
								showingDeleteAlert = true
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
						.swipeActions(edge: .leading) {
							if group.items.contains(where: { $0.state == .pending || $0.state == .sending || $0.state == .waitingForAck }) {
								Button {
									Task {
										for item in group.items {
											await MessageRetryQueueManager.shared.cancelRetry(forItemId: item.id)
										}
										await refreshQueue()
									}
								} label: {
									Label("Stop", systemImage: "stop.circle")
								}
								.tint(.orange)
							}
						}
				}
			}
			.listStyle(.plain)
		}
	}

	@ViewBuilder
	private var iPadContent: some View {
		if groupedItems.isEmpty {
			ContentUnavailableView(
				queueItems.isEmpty ? "Queue Empty" : "No Matching Items",
				systemImage: queueItems.isEmpty ? "checkmark.circle" : "magnifyingglass"
			)
		} else {
			Table(groupedItems, selection: Binding(
				get: { selectedGroup?.originalMessageId },
				set: { newId in
					selectedGroup = groupedItems.first { $0.originalMessageId == newId }
				}
			)) {
				TableColumn("Type") { group in
					HStack(spacing: 4) {
						Image(systemName: group.messageType.icon)
							.symbolRenderingMode(.hierarchical)
							.foregroundColor(group.messageType.color)
						Text(group.messageType.rawValue.capitalized)
					}
				}
				.width(min: 80, max: 120)

				TableColumn("Retries") { group in
					let pendingItems = group.items.filter { $0.state == .pending }
					if pendingItems.count > 1 {
						Text("Attempts \(pendingItems.first?.displayAttemptNumber ?? 0)-\(pendingItems.last?.displayAttemptNumber ?? 0)")
					} else if let first = group.items.first {
						Text("Attempt \(first.displayAttemptNumber)")
					}
				}
				.width(min: 80, max: 100)

				TableColumn("Next") { group in
					if let nextRetry = group.nextRetryDate {
						let seconds = Int(nextRetry.timeIntervalSince(currentDate))
						if seconds > 0 {
							Text("\(seconds)s")
								.foregroundColor(.orange)
						} else {
							Text("Now")
								.foregroundColor(.red)
						}
					} else {
						Text("-")
					}
				}
				.width(min: 60, max: 80)

				TableColumn("Status") { group in
					let state = group.items.first?.state ?? .pending
					Text(state.rawValue.capitalized)
						.font(.caption)
						.foregroundColor(state.color)
				}
				.width(min: 100, max: 120)
			}
			.onChange(of: selectedGroup) { _, newGroup in
				if newGroup != nil {
					selectedGroup = newGroup
				}
			}
		}
	}
}

struct RetryGroup: Identifiable, Hashable {
	let id: Int64
	let originalMessageId: Int64
	let messageType: MessageType
	let items: [RetryQueueItem]
	let createdAt: Date

	var nextRetryDate: Date? {
		items.filter { $0.state == .pending }.map { $0.nextRetryDate }.min()
	}

	init(originalMessageId: Int64, messageType: MessageType, items: [RetryQueueItem], createdAt: Date) {
		self.id = originalMessageId
		self.originalMessageId = originalMessageId
		self.messageType = messageType
		self.items = items
		self.createdAt = createdAt
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(originalMessageId)
	}

	static func == (lhs: RetryGroup, rhs: RetryGroup) -> Bool {
		lhs.originalMessageId == rhs.originalMessageId
	}
}

struct RetryGroupKey: Hashable {
	let originalMessageId: Int64
	let messageType: MessageType
}

struct RetryGroupRow: View {
	let group: RetryGroup
	let currentDate: Date

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: group.messageType.icon)
				.symbolRenderingMode(.hierarchical)
				.font(.title2)
				.foregroundColor(group.messageType.color)
				.frame(width: 32)

			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text(group.messageType.rawValue.capitalized)
						.font(.headline)

					let state = group.items.first?.state ?? .pending
					Text(state.rawValue.capitalized)
						.font(.caption)
						.padding(.horizontal, 8)
						.padding(.vertical, 2)
						.background(state.color.opacity(0.2))
						.foregroundColor(state.color)
						.clipShape(Capsule())
				}

				HStack(spacing: 8) {
					Text(group.originalMessageId.toHex())
						.font(.caption.monospaced())

					Text(group.messageType.rawValue.capitalized)
						.font(.caption)
						.foregroundColor(.secondary)
				}

				HStack(spacing: 8) {
					let pendingItems = group.items.filter { $0.state == .pending }
					if pendingItems.count > 1 {
						Label {
							Text("Attempts \(pendingItems.first?.displayAttemptNumber ?? 0)-\(pendingItems.last?.displayAttemptNumber ?? 0)")
								.font(.caption)
								.foregroundColor(.secondary)
						} icon: {
							Image(systemName: "arrow.clockwise")
						}
					} else if let first = group.items.first {
						Label {
							Text("Attempt \(first.displayAttemptNumber)")
								.font(.caption)
								.foregroundColor(.secondary)
						} icon: {
							Image(systemName: "arrow.clockwise")
						}
					}

					Spacer()

					if let nextRetry = group.nextRetryDate {
						let seconds = Int(nextRetry.timeIntervalSince(currentDate))
						if seconds > 0 {
							Text("In \(seconds)s")
								.font(.caption)
								.foregroundColor(.orange)
								.monospacedDigit()
						} else {
							Text("Now")
								.font(.caption)
								.foregroundColor(.red)
						}
					}
				}
			}

			Spacer()
		}
		.padding(.vertical, 4)
	}
}

struct RetryQueueDetailSheet: View {
	let group: RetryGroup
	let allItems: [RetryGroup]
	@Environment(\.dismiss) private var dismiss
	@State private var isCancelling = false
	
	private var currentState: RetryState {
		group.items.first?.state ?? .pending
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 16) {
					Section {
						HStack {
							Image(systemName: group.messageType.icon)
								.symbolRenderingMode(.hierarchical)
								.font(.largeTitle)
								.foregroundColor(group.messageType.color)

							VStack(alignment: .leading) {
								Text(group.messageType.rawValue.capitalized)
									.font(.headline)

								Text("ID: \(group.originalMessageId.toHex())")
									.font(.caption.monospaced())
									.foregroundColor(.secondary)
							}

							Spacer()

							Text(currentState.rawValue.capitalized)
								.font(.caption)
								.padding(.horizontal, 12)
								.padding(.vertical, 6)
								.background(currentState.color.opacity(0.2))
								.foregroundColor(currentState.color)
								.clipShape(Capsule())
						}
					}

					Divider()

						Section("Retry Attempts") {
							ForEach(group.items.indices, id: \.self) { index in
								let item = group.items[index]
								HStack {
								Image(systemName: item.state.icon)
									.symbolRenderingMode(.hierarchical)
									.foregroundColor(item.state.color)

									VStack(alignment: .leading) {
										Text("Attempt \(item.displayAttemptNumber)")
											.font(.subheadline)

									HStack {
										if let currentId = item.currentPacketId {
											Text("ID: \(currentId.toHex())")
												.font(.caption.monospaced())
										} else {
											Text("Not sent yet")
												.font(.caption)
										}

										if item.state == .pending {
											Text("•")
												.foregroundColor(.secondary)

											let seconds = Int(item.nextRetryDate.timeIntervalSince(Date()))
											if seconds > 0 {
												Text("In \(seconds)s")
													.font(.caption)
													.foregroundColor(.orange)
													.monospacedDigit()
											}
										}
									}
								}

								Spacer()

								Text(item.state.rawValue.capitalized)
									.font(.caption)
									.foregroundColor(item.state.color)
							}
							.padding(.vertical, 4)
						}
					}

					Divider()

					Section("Created") {
						HStack {
							Text("Time:")
							Spacer()
							Text(group.createdAt.formatted(date: .abbreviated, time: .shortened))
						}
					}

					Section {
						let hasPendingRetries = group.items.contains(where: { $0.state == .pending || $0.state == .sending || $0.state == .waitingForAck })
						Button(role: .destructive) {
							isCancelling = true
						} label: {
							HStack {
								Spacer()
								if isCancelling {
									ProgressView()
								} else {
									Label("Cancel All Retries", systemImage: "stop.circle.fill")
								}
								Spacer()
							}
						}
						.disabled(isCancelling || !hasPendingRetries)
					}
				}
				.padding()
			}
			.navigationTitle("Retry Details")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Done") {
						dismiss()
					}
				}
			}
			.task {
				if isCancelling {
					for item in group.items {
						await MessageRetryQueueManager.shared.cancelRetry(forItemId: item.id)
					}
					isCancelling = false
					dismiss()
				}
			}
		}
	}
}

extension RetryState {
	var icon: String {
		switch self {
		case .pending: return "clock"
		case .sending: return "arrow.up.circle"
		case .waitingForAck: return "hourglass"
		case .completed: return "checkmark.circle"
		case .failed: return "xmark.circle"
		case .cancelled: return "minus.circle"
		}
	}
}

extension RetryQueueDetailSheet: Identifiable {
	var id: Int64 { group.originalMessageId }
}

extension MessageType {
	var icon: String {
		switch self {
		case .text: return "message"
		case .position: return "location"
		case .waypoint: return "mappin.circle"
		case .admin: return "lock.shield"
		case .traceroute: return "point.topleft.down.curvedto.point.bottomright.up"
		case .nodeInfo: return "person.circle"
		case .unknown: return "questionmark.circle"
		}
	}
	
	var color: Color {
		switch self {
		case .text: return .blue
		case .position: return .green
		case .waypoint: return .orange
		case .admin: return .purple
		case .traceroute: return .cyan
		case .nodeInfo: return .indigo
		case .unknown: return .gray
		}
	}
}

extension RetryState {
	var color: Color {
		switch self {
		case .pending: return .orange
		case .sending: return .blue
		case .waitingForAck: return .purple
		case .completed: return .green
		case .failed: return .red
		case .cancelled: return .gray
		}
	}
}
