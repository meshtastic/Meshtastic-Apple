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
	/// Where a link goes with no window open: the app's first router.
	let fallback: Router

	nonisolated init(fallback: Router) {
		self.fallback = fallback
	}

	func register(_ window: RadioWindow, router: Router) {
		entries.removeAll { $0.router === router }
		entries.append(Entry(window: window, router: router))
	}

	func unregister(router: Router) {
		entries.removeAll { $0.router === router }
	}

	func activated(_ window: RadioWindow) {
		lastActive = window
	}

	/// Every open window's router, for what applies to all of them (popping detail views before
	/// a store reset). The fallback when none is open.
	var allRouters: [Router] {
		entries.isEmpty ? [fallback] : entries.map(\.router)
	}

	/// Which window a link goes to (W-05):
	/// - a direct message: the window of the radio that received it (`radio`);
	/// - a channel message: the first window, in the order they opened, whose radio has the
	///   channel (`channelRadios`, which includes `radio`);
	/// - otherwise, or when no window matches, the window the user was last in, then the first.
	/// `windows` pairs each open window with its radio's node number.
	static func choose(
		windows: [(window: RadioWindow, radioNum: Int64?)],
		radio: Int64?,
		channelRadios: Set<Int64>?,
		lastActive: RadioWindow?
	) -> RadioWindow? {
		if let channelRadios {
			if let match = windows.first(where: { $0.radioNum.map(channelRadios.contains) ?? false }) {
				return match.window
			}
		} else if let radio, let match = windows.first(where: { $0.radioNum == radio }) {
			return match.window
		}
		if let lastActive, windows.contains(where: { $0.window == lastActive }) {
			return lastActive
		}
		return windows.first?.window
	}

	/// Routes a `meshtastic://` link on the window it's about.
	func route(url: URL, manager: AccessoryManager) {
		router(for: url, manager: manager).route(url: url)
	}

	/// The router of the window `url` is about. A messages link names the radio it came in on
	/// (`radio=`); a channel's also counts every connected radio that has that channel.
	func router(for url: URL, manager: AccessoryManager) -> Router {
		guard entries.count > 1 else { return entries.first?.router ?? fallback }
		let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
		let radio = items.first(where: { $0.name == "radio" })?.value.flatMap(Int64.init)
		let channelId = items.first(where: { $0.name == "channelId" })?.value.flatMap(Int32.init)
		var channelRadios: Set<Int64>?
		if let channelId, let radio {
			channelRadios = Self.radiosWithChannel(channelId, of: radio, among: manager.connectedRadioNums, context: manager.context)
		}
		let windows = entries.map { (window: $0.window, radioNum: manager.nodeNum(for: $0.window)) }
		let chosen = Self.choose(windows: windows, radio: radio, channelRadios: channelRadios, lastActive: lastActive)
		return entries.first { $0.window == chosen }?.router ?? fallback
	}

	/// The radios among `radios` that have the channel radio `radio` has in slot `index`,
	/// `radio` itself included.
	private static func radiosWithChannel(_ index: Int32, of radio: Int64, among radios: [Int64], context: ModelContext) -> Set<Int64> {
		let keys = (try? MultiRadioBackfill.channelKeysByIndex(for: radio, in: context, updateStored: false)) ?? [:]
		guard let key = keys[index] else { return [radio] }
		return Set(ChannelMessageQuery.slots(for: key, among: radios, in: context).map(\.radio)).union([radio])
	}
}
