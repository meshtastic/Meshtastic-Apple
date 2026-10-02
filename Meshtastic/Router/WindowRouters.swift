//
//  WindowRouters.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import OSLog
import SwiftData

/// The open windows and their routers (feature 021, D-19, T308). Each window navigates on its
/// own, so opening a node in one doesn't move another. A deep link or a notification tap goes to
/// the window whose radio it's about (W-05).
///
/// A node switch pops the detail views in every window before it touches the store, and that pop
/// has to happen in the call, not on a later `onChange`: the views are still mounted, holding
/// model objects the reset is about to destroy (`popAllStacks()`). Windows that show no radio's
/// app, such as the Mesh Map window, register only for that.
@MainActor
final class WindowRouters {
	struct Entry {
		let window: RadioWindow
		let router: Router
	}

	/// Open windows, in the order they opened.
	private(set) var entries: [Entry] = []
	/// The window the user was last in.
	private(set) var lastActive: RadioWindow?
	/// Routers of windows that links don't go to (the Mesh Map window), popped with the rest.
	private var popOnly: [UUID: Router] = [:]
	/// A link that came with no window open (a notification tap that launched the app). The next
	/// window to open takes it.
	private(set) var heldLink: URL?

	nonisolated init() {}

	/// Opens a radio's window (on the Mac, set by its windows): a link about a radio whose window
	/// is hidden or closed reopens it (W-05, review V11 W4).
	var openWindowHandler: ((RadioWindow) -> Void)?
	/// Links waiting for a radio's window to open, by device id.
	private(set) var pendingLinks: [UUID: URL] = [:]

	func register(_ window: RadioWindow, router: Router) {
		entries.removeAll { $0.router === router }
		entries.append(Entry(window: window, router: router))
		if let deviceId = window.deviceId, let url = pendingLinks.removeValue(forKey: deviceId) {
			router.route(url: url)
		} else if let url = heldLink {
			heldLink = nil
			router.route(url: url)
		}
	}

	func unregister(router: Router) {
		entries.removeAll { $0.router === router }
	}

	/// A window that links don't go to, popped with the rest on a store reset.
	@discardableResult
	func registerPopOnly(_ router: Router) -> UUID {
		let id = UUID()
		popOnly[id] = router
		return id
	}

	func unregisterPopOnly(_ id: UUID) {
		popOnly.removeValue(forKey: id)
	}

	func activated(_ window: RadioWindow) {
		lastActive = window
	}

	/// Every open window's router, for what applies to all of them.
	var allRouters: [Router] {
		entries.map(\.router) + popOnly.values
	}

	/// Drops every detail stack in every window and leaves each window on its tab, so a store
	/// reset can unmount doomed model objects without moving every window to the same tab.
	func popAllStacks() {
		for router in allRouters {
			router.popAllStacks()
		}
	}

	/// The window whose radio a link is about (W-05), or nil when none is open:
	/// - a direct message: the window of the radio that received it (`radio`);
	/// - a channel message: the first window, in the order they opened, whose radio has the
	///   channel (`channelRadios`, which includes `radio`).
	/// `windows` pairs each open window with its radio's node number.
	static func matching(
		windows: [(window: RadioWindow, radioNum: Int64?)],
		radio: Int64?,
		channelRadios: Set<Int64>?
	) -> RadioWindow? {
		if let channelRadios {
			return windows.first(where: { $0.radioNum.map(channelRadios.contains) ?? false })?.window
		}
		guard let radio else { return nil }
		return windows.first(where: { $0.radioNum == radio })?.window
	}

	/// Where a link goes with no window of its radio open: the window the user was last in, then
	/// the first.
	static func fallback(windows: [RadioWindow], lastActive: RadioWindow?) -> RadioWindow? {
		if let lastActive, windows.contains(lastActive) {
			return lastActive
		}
		return windows.first
	}

	/// `matching`, else `fallback`.
	static func choose(
		windows: [(window: RadioWindow, radioNum: Int64?)],
		radio: Int64?,
		channelRadios: Set<Int64>?,
		lastActive: RadioWindow?
	) -> RadioWindow? {
		matching(windows: windows, radio: radio, channelRadios: channelRadios)
			?? fallback(windows: windows.map(\.window), lastActive: lastActive)
	}

	/// Routes a `meshtastic://` link on the window it's about. On the Mac, when that radio's
	/// window is hidden or closed, it's opened and the link waits for it (review V11 W4).
	func route(url: URL, manager: AccessoryManager) {
		let (radio, channelRadios) = Self.radios(of: url, manager: manager)
		let windows = entries.map { (window: $0.window, radioNum: Self.radioNum(of: $0.window, manager: manager)) }
		if let match = Self.matching(windows: windows, radio: radio, channelRadios: channelRadios),
		   let router = entries.first(where: { $0.window == match })?.router {
			router.route(url: url)
			return
		}
		// The radio it came in on, or for a channel another connected radio that has it.
		let target = radio.flatMap { channelRadios?.contains($0) ?? true ? $0 : nil } ?? channelRadios?.sorted().first
		if let openWindowHandler, let target, let deviceId = manager.deviceId(ofRadio: target) {
			pendingLinks[deviceId] = url
			openWindowHandler(RadioWindow(deviceId: deviceId))
			return
		}
		// A link about no radio with no window open, on the Mac: a connected radio's window, since
		// the Connect window shows no router (review V12 Y4).
		if let openWindowHandler, radio == nil, entries.isEmpty, let deviceId = manager.connectedRadios.first?.id {
			pendingLinks[deviceId] = url
			openWindowHandler(RadioWindow(deviceId: deviceId))
			return
		}
		let chosen = Self.fallback(windows: windows.map(\.window), lastActive: lastActive)
		guard let router = entries.first(where: { $0.window == chosen })?.router else {
			// No window open yet: the first one to open takes it.
			heldLink = url
			return
		}
		router.route(url: url)
	}

	/// The router `route(url:manager:)` would use now, without opening anything; nil with no
	/// window open.
	func router(for url: URL, manager: AccessoryManager) -> Router? {
		let (radio, channelRadios) = Self.radios(of: url, manager: manager)
		let windows = entries.map { (window: $0.window, radioNum: Self.radioNum(of: $0.window, manager: manager)) }
		let chosen = Self.choose(windows: windows, radio: radio, channelRadios: channelRadios, lastActive: lastActive)
		return entries.first { $0.window == chosen }?.router
	}

	/// A messages link names the radio it came in on (`radio=`); a channel's also counts every
	/// connected radio that has that channel.
	private static func radios(of url: URL, manager: AccessoryManager) -> (Int64?, Set<Int64>?) {
		let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
		let radio = items.first(where: { $0.name == "radio" })?.value.flatMap(Int64.init)
		let channelId = items.first(where: { $0.name == "channelId" })?.value.flatMap(Int32.init)
		guard let channelId, let radio else { return (radio, nil) }
		return (radio, radiosWithChannel(channelId, of: radio, among: manager.connectedRadioNums, context: manager.context))
	}

	/// A window's radio, also while it's off (`radioNodeNum(for:)`), so its links still find it.
	private static func radioNum(of window: RadioWindow, manager: AccessoryManager) -> Int64? {
		if let connected = manager.nodeNum(for: window) { return connected }
		let known = manager.radioNodeNum(for: window)
		return known == 0 ? nil : known
	}

	/// The radios among `radios` that have the channel radio `radio` has in slot `index`,
	/// `radio` itself included.
	private static func radiosWithChannel(_ index: Int32, of radio: Int64, among radios: [Int64], context: ModelContext) -> Set<Int64> {
		let keys = (try? MultiRadioBackfill.channelKeysByIndex(for: radio, in: context, updateStored: false)) ?? [:]
		guard let key = keys[index] else { return [radio] }
		return Set(ChannelMessageQuery.slots(for: key, among: radios, in: context).map(\.radio)).union([radio])
	}
}
