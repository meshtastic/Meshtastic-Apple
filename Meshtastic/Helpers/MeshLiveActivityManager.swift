//
//  MeshLiveActivityManager.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/17/26.
//
//  Starts, updates and ends the Live Activity. One runs at a time, in the mode
//  the user picked: a mesh status glance, or one tracked node. Mesh status
//  follows the widget snapshot; a tracked node is re-read when a packet from
//  it arrives. A dropped link marks the activity disconnected rather than
//  ending it, because the app reconnects through the same state; only a
//  disconnect the user asked for, or a radio switch, ends it.
//
//  The class compiles everywhere so its callers need no platform checks; on
//  platforms without Live Activities every method does nothing.
//

import Combine
import Foundation
import OSLog
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class MeshLiveActivityManager: ObservableObject {
	static let shared = MeshLiveActivityManager()

	/// The running activity's mode; nil when none is running.
	@Published private(set) var currentMode: LiveActivityMode?
	/// The tracked node's short name, when tracking one.
	@Published private(set) var trackedNodeShortName: String?
	/// When the running activity stops updating; the system caps it at 8 hours.
	@Published private(set) var updatesEndAt: Date?
	/// Live Activities are supported here and turned on in Settings.
	@Published private(set) var isAvailable = false

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
	private typealias Attributes = MeshLiveActivityAttributes
	private typealias Content = MeshLiveActivityAttributes.ContentState

	/// Mesh status: no change for this long, and the activity reads as stale.
	/// LocalStats arrive about every 15 minutes.
	private static let meshStatusStaleAfter: TimeInterval = 20 * 60
	/// Track a node: stale once it hasn't been heard for this long, the same
	/// window the app uses for online.
	private static let trackedNodeStaleAfter: TimeInterval = 2 * 3600
	/// A packet from the tracked node arrives before its writes land.
	private static let trackedReadDelay: Duration = .seconds(3)
	/// The id of the activity CarPlay started, kept across relaunches so the
	/// car disconnecting still ends it.
	private static let carPlayActivityKey = "liveActivityStartedByCarPlay"

	private var activity: Activity<Attributes>?
	private var lastContent: Content?
	private var lastStaleDate: Date?
	/// The connection as the activity shows it; the one place that sets it.
	private var connection: WidgetConnectionState = .disconnected
	/// The newest battery reading handed over from the radio's telemetry, for
	/// the radio it came from.
	private var radioBattery: (num: Int64, level: Int32)?
	private var startTask: Task<Void, Never>?
	private var stateTask: Task<Void, Never>?
	private var enablementTask: Task<Void, Never>?
	private var trackedReadTask: Task<Void, Never>?
	/// True while a read waits out the delay after a packet; a read the broker
	/// asks for then would land before the packet's writes.
	private var trackedReadIsDelayed = false
	private var packetSubscription: AnyCancellable?
#endif

	private init() {}

	// MARK: - Lifecycle

	/// At launch: ends activities of the old type, picks up one of ours that
	/// survived a relaunch, and follows the Settings switch.
	func start() {
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
		let authorization = ActivityAuthorizationInfo()
		isAvailable = authorization.areActivitiesEnabled
		enablementTask = Task { [weak self] in
			for await enabled in authorization.activityEnablementUpdates {
				self?.isAvailable = enabled
			}
		}

		// The local stats activity this replaced; nothing updates it any more.
		for old in Activity<MeshActivityAttributes>.activities {
			Task { await old.end(nil, dismissalPolicy: .immediate) }
		}

		// The list keeps ended activities while they're still on screen; only a
		// live one can be picked up.
		let all = Activity<Attributes>.activities
		let live = all.filter { $0.activityState == .active || $0.activityState == .stale }
		if let survivor = live.first {
			adopt(survivor)
			// Shown disconnected until the radio reconnects; a different radio ends it.
			connection = .disconnected
			pushCurrent()
		}
		for other in all where other.id != live.first?.id {
			Task { await other.end(nil, dismissalPolicy: .immediate) }
		}

		packetSubscription = AccessoryManager.shared.packetEvents
			.receive(on: DispatchQueue.main)
			.sink { [weak self] event in
				MainActor.assumeIsolated {
					self?.packetHeard(from: event.from)
				}
			}
#endif
	}

	/// Starts a Live Activity in `mode`, replacing any that's running. Starts
	/// run one at a time; a newer one cancels an older one still in progress.
	func start(mode: LiveActivityMode, startedByCarPlay: Bool = false) {
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
		guard let radioNum = canStart(mode) else { return }

		let context = PersistenceController.shared.context
		let radioUser = getNodeInfo(id: radioNum, context: context)?.user
		var nodeShortName: String?
		var nodeLongName: String?
		if let num = mode.trackedNodeNum {
			let user = getNodeInfo(id: num, context: context)?.user
			nodeShortName = user?.shortName ?? String(num.toHex().suffix(4))
			nodeLongName = user?.longName?.addingVariationSelectors ?? num.toHex()
		}
		let attributes = Attributes(
			mode: mode,
			startedAt: Date(),
			radioNum: radioNum,
			radioShortName: radioUser?.shortName ?? "?",
			radioLongName: radioUser?.longName?.addingVariationSelectors ?? String(localized: "Meshtastic"),
			nodeShortName: nodeShortName,
			nodeLongName: nodeLongName
		)

		let previous = startTask
		previous?.cancel()
		startTask = Task {
			_ = await previous?.value
			guard !Task.isCancelled else { return }
			await endAll()
			var content = Content(connection: connection, updatedAt: Date())
			if mode == .meshStatus {
				content = meshStatusContent(from: WidgetSnapshotStore.load(), radioNum: radioNum)
			} else if let num = mode.trackedNodeNum,
					  case .found(let reading) = await MeshPackets.shared.liveActivityNodeReading(num: num, radioNum: radioNum) {
				content = trackedContent(from: reading)
			}
			// The link, the radio or the user may have moved on while this waited.
			guard !Task.isCancelled, canStart(mode) == radioNum else { return }
			content.connection = connection
			let staleDate = staleDate(for: mode, content: content)
			do {
				let started = try Activity.request(
					attributes: attributes,
					content: ActivityContent(state: content, staleDate: staleDate),
					pushType: nil
				)
				UserDefaults.standard.set(startedByCarPlay ? started.id : nil, forKey: Self.carPlayActivityKey)
				adopt(started)
				lastContent = content
				lastStaleDate = staleDate
			} catch {
				Logger.services.error("🛰️ Live Activity didn't start: \(error.localizedDescription, privacy: .public)")
			}
		}
#endif
	}

	/// Ends the running Live Activity.
	func stop() {
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
		startTask?.cancel()
		Task { await endAll() }
#endif
	}

	/// CarPlay starts a mesh status activity when the car connects. When it
	/// disconnects, only that one ends; one the user started keeps running.
	func endIfStartedByCarPlay() {
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
		guard let activity,
			  UserDefaults.standard.string(forKey: Self.carPlayActivityKey) == activity.id else { return }
		stop()
#endif
	}

	// MARK: - Updates

	/// Called by the widget broker after each snapshot write.
	func meshStatusDidUpdate(_ snapshot: WidgetSnapshot) {
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
		guard let activity else { return }
		switch activity.attributes.mode {
		case .meshStatus:
			pushContent(meshStatusContent(from: snapshot, radioNum: activity.attributes.radioNum))
		case .trackNode:
			// The broker also runs after a node is deleted, ignored or the
			// database is cleared; a fresh read catches all three.
			scheduleTrackedRead(after: .zero)
		}
#endif
	}

	/// The connected radio's battery, from its device telemetry, with the radio
	/// it came from.
	func radioBatteryDidUpdate(_ level: Int32, radioNum: Int64) {
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
		radioBattery = (radioNum, level)
		guard let activity, activity.attributes.mode == .meshStatus,
			  activity.attributes.radioNum == radioNum, var content = lastContent,
			  content.radioBattery != level else { return }
		content.radioBattery = level
		content.updatedAt = Date()
		pushContent(content)
#endif
	}

	/// Called on every connection state change.
	func connectionStateChanged(_ state: AccessoryManagerState) {
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
		let newConnection = Self.connection(for: state)
		// A node database download changes state once per node.
		guard newConnection != connection else { return }
		connection = newConnection
		guard let activity else { return }

		let accessoryManager = AccessoryManager.shared
		switch newConnection {
		case .disconnected:
			// A dropped link and a cold launch both pass through here before
			// reconnecting, so only a disconnect the user asked for ends it.
			if accessoryManager.userRequestedConnectionCancellation || accessoryManager.isSwitchingDevices {
				stop()
				return
			}
		case .connected:
			// A different radio: the activity describes the old one's mesh.
			if let activeNum = accessoryManager.activeDeviceNum, activeNum != activity.attributes.radioNum {
				stop()
				return
			}
			if activity.attributes.mode.trackedNodeNum != nil {
				scheduleTrackedRead(after: .zero)
			}
		case .connecting:
			break
		}
		pushCurrent()
#endif
	}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
	/// The radio to start for, or nil when an activity can't start now.
	private func canStart(_ mode: LiveActivityMode) -> Int64? {
		let accessoryManager = AccessoryManager.shared
		guard isAvailable,
			  accessoryManager.isConnected,
			  let radioNum = accessoryManager.activeDeviceNum,
			  accessoryManager.lockdownCoordinator?.isBlockingSession != true,
			  mode.trackedNodeNum != radioNum else { return nil }
		return radioNum
	}

	private static func connection(for state: AccessoryManagerState) -> WidgetConnectionState {
		switch state {
		case .subscribed, .retrievingDatabase:
			return .connected
		case .connecting, .communicating, .retrying:
			return .connecting
		case .uninitialized, .idle, .discovering:
			return .disconnected
		}
	}

	private func packetHeard(from num: Int64) {
		guard let tracked = activity?.attributes.mode.trackedNodeNum, tracked == num else { return }
		scheduleTrackedRead(after: Self.trackedReadDelay)
	}

	private func scheduleTrackedRead(after delay: Duration) {
		guard let activity, let num = activity.attributes.mode.trackedNodeNum else { return }
		guard !PersistenceController.shared.isProvisionalPendingFirstUnlock else { return }
		// A read waiting out the delay after a packet covers this request too,
		// and reads after the packet's writes land.
		if delay == .zero, trackedReadIsDelayed { return }
		let radioNum = activity.attributes.radioNum
		trackedReadTask?.cancel()
		trackedReadIsDelayed = delay > .zero
		trackedReadTask = Task { [weak self] in
			if delay > .zero {
				try? await Task.sleep(for: delay)
			}
			guard !Task.isCancelled else { return }
			self?.trackedReadIsDelayed = false
			let lookup = await MeshPackets.shared.liveActivityNodeReading(num: num, radioNum: radioNum)
			guard !Task.isCancelled, let self else { return }
			switch lookup {
			case .missing:
				// Deleted, evicted or cleared: nothing left to track.
				self.stop()
			case .found(let reading) where reading.ignored:
				self.stop()
			case .found(let reading):
				self.pushContent(self.trackedContent(from: reading))
			case .unavailable:
				// The next packet or broker build reads again.
				break
			}
		}
	}

	// MARK: - Content

	private func meshStatusContent(from snapshot: WidgetSnapshot?, radioNum: Int64) -> Content {
		var content = Content(connection: connection, updatedAt: Date())
		guard let snapshot, snapshot.radioNodeNum == radioNum else { return content }
		content.nodesOnline = snapshot.localStats?.nodesOnline
		content.nodesTotal = snapshot.localStats?.nodesTotal
		content.statsAt = snapshot.localStats?.statsAt
		content.unreadCount = snapshot.unreadChannelMessages + snapshot.unreadDirectMessages
		// The handed-over reading is newer than the snapshot's, which is read
		// before the telemetry's debounced save lands.
		if let radioBattery, radioBattery.num == radioNum {
			content.radioBattery = radioBattery.level
		} else {
			content.radioBattery = snapshot.radioBatteryLevel
		}
		return content
	}

	private func trackedContent(from reading: MeshPackets.LiveActivityNodeReading) -> Content {
		var content = Content(connection: connection, updatedAt: Date())
		content.nodeBattery = reading.battery
		content.signalRating = reading.signalRating
		content.lastHeard = reading.lastHeard
		content.hopsAway = reading.hopsAway
		content.distanceMeters = reading.distanceMeters
		return content
	}

	private func staleDate(for mode: LiveActivityMode, content: Content) -> Date {
		guard content.connection == .connected else {
			// Already stale: keep the date it went stale, so repeat updates
			// compare equal and are skipped.
			if let lastStaleDate, lastStaleDate <= Date() { return lastStaleDate }
			return Date()
		}
		switch mode {
		case .meshStatus:
			return Date().addingTimeInterval(Self.meshStatusStaleAfter)
		case .trackNode:
			return (content.lastHeard ?? Date()).addingTimeInterval(Self.trackedNodeStaleAfter)
		}
	}

	/// Re-sends the last content with the current connection.
	private func pushCurrent() {
		guard activity != nil else { return }
		var content = lastContent ?? Content(connection: connection, updatedAt: Date())
		content.connection = connection
		pushContent(content)
	}

	/// Sends content when something visible changed or the stale date moved.
	/// Mesh status pushes its stale date forward on every build, so it's only
	/// re-sent for that when the current one is close, which keeps a quiet but
	/// healthy mesh from reading as stale.
	private func pushContent(_ newContent: Content) {
		guard let activity else { return }
		var content = newContent
		content.connection = connection
		let staleDate = staleDate(for: activity.attributes.mode, content: content)
		if let lastContent, content.sameReadings(as: lastContent), let lastStaleDate {
			let sameStaleDate = abs(staleDate.timeIntervalSince(lastStaleDate)) < 1
			let farFromStale = lastStaleDate.timeIntervalSinceNow > 5 * 60 && staleDate >= lastStaleDate
			if sameStaleDate || farFromStale { return }
		}
		lastContent = content
		lastStaleDate = staleDate
		Task {
			await activity.update(ActivityContent(state: content, staleDate: staleDate))
		}
	}

	private func adopt(_ adopted: Activity<Attributes>) {
		activity = adopted
		currentMode = adopted.attributes.mode
		trackedNodeShortName = adopted.attributes.nodeShortName
		updatesEndAt = adopted.attributes.updatesEndAt
		lastContent = adopted.content.state
		lastStaleDate = adopted.content.staleDate
		stateTask?.cancel()
		stateTask = Task { [weak self] in
			for await state in adopted.activityStateUpdates {
				if state == .ended || state == .dismissed {
					self?.clear(adopted.id)
					return
				}
			}
		}
	}

	private func clear(_ id: String) {
		guard activity?.id == id else { return }
		activity = nil
		currentMode = nil
		trackedNodeShortName = nil
		updatesEndAt = nil
		lastContent = nil
		lastStaleDate = nil
		trackedReadTask?.cancel()
		trackedReadIsDelayed = false
		stateTask?.cancel()
		if UserDefaults.standard.string(forKey: Self.carPlayActivityKey) == id {
			UserDefaults.standard.removeObject(forKey: Self.carPlayActivityKey)
		}
	}

	/// Ends every activity of ours with its last content.
	private func endAll() async {
		let ending = Activity<Attributes>.activities
		if let activity {
			clear(activity.id)
		}
		for running in ending {
			var final = running.content.state
			final.connection = connection
			await running.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate)
		}
	}
#endif
}
