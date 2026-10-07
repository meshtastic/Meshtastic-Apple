//
//  RadioWindowViews.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

// MARK: - One window per radio on the Mac (feature 021, D-19, T310–T313)

/// Which radios' windows to open. A radio's window opens once when it connects; closing it only
/// hides it (W-01), so it isn't opened again while the radio stays connected. Disconnecting the
/// radio (W-02) keeps its window, showing it off, and forgets it here, so a window closed since
/// opens again the next time it connects. Removing it forgets it too.
@MainActor
final class RadioWindowTracker {
	private(set) var opened: Set<UUID> = []
	/// Radios the user disconnected that were still connected when told (review V28-1): forgotten
	/// once they've gone, so a change of another radio meanwhile doesn't open their window again.
	private var leaving: Set<UUID> = []

	nonisolated init() {}

	/// The radios among `connected` whose window should open now, and marks them opened.
	func toOpen(connected: Set<UUID>) -> [UUID] {
		let gone = leaving.subtracting(connected)
		opened.subtract(gone)
		leaving.subtract(gone)
		let new = connected.subtracting(opened)
		opened.formUnion(new)
		return new.sorted { $0.uuidString < $1.uuidString }
	}

	/// `deviceId` was removed by the user, or has gone: its window opens again when it's back.
	func forget(_ deviceId: UUID) {
		opened.remove(deviceId)
		leaving.remove(deviceId)
	}

	/// `deviceId` was disconnected by the user. The Disconnect says so before the link closes
	/// (review V28-1), so while it's still among `connected` it's forgotten once it has gone.
	func forgetOnceGone(_ deviceId: UUID, connected: Set<UUID>) {
		if connected.contains(deviceId) {
			leaving.insert(deviceId)
		} else {
			forget(deviceId)
		}
	}

	// MARK: The last window (T393)

	/// How many views each radio's window has on screen. A store reset or a renumber swaps a
	/// window's view for a new one for the same radio (`.id(databaseResetID)`), and the new one
	/// appears before the old one goes, so a set would lose the window (review V33-1).
	private var windowViews: [UUID: Int] = [:]
	/// Radio windows told to close because their radio was removed or forgotten.
	private var closingWindows: Set<UUID> = []

	/// The radios whose window is on screen. A window closed by hand is hidden (W-01), not here.
	var shownWindows: Set<UUID> { Set(windowViews.keys) }

	func windowAppeared(_ deviceId: UUID) {
		let views = windowViews[deviceId, default: 0] + 1
		windowViews[deviceId] = views
		// A window opening again isn't closing; a swap of a closing window's view still is.
		if views == 1 {
			closingWindows.remove(deviceId)
		}
	}

	func windowDisappeared(_ deviceId: UUID) {
		let views = windowViews[deviceId, default: 0] - 1
		if views > 0 {
			windowViews[deviceId] = views
		} else {
			windowViews[deviceId] = nil
			closingWindows.remove(deviceId)
		}
	}

	/// `deviceId`'s window closes because its radio was removed or forgotten. Whether no window is
	/// left once it has, so the Connect window opens in its place, as the one window on `main`
	/// stays (T393). `connectWindows` counts the Connect windows open. When several close at once
	/// (Clear App Data with several radios), the last one told opens it, once.
	func closesLastWindow(_ deviceId: UUID, connectWindows: Int) -> Bool {
		closingWindows.insert(deviceId)
		return connectWindows == 0 && shownWindows.subtracting(closingWindows).isEmpty
	}
}

/// Opens each radio's window when it connects (T310). In every window on the Mac, so one is
/// always there to do it; the tracker makes sure a radio's window is opened only once.
struct RadioWindowOpener: ViewModifier {
	@ObservedObject private var accessoryManager = AccessoryManager.shared
	let tracker: RadioWindowTracker
	@Environment(\.openWindow) private var openWindow

	private var connectedRadios: Set<UUID> {
		Set(accessoryManager.connectedRadios.map(\.id).filter { accessoryManager.linkStatus(of: $0).isConnected })
	}

	func body(content: Content) -> some View {
		if RadioWindows.areEnabled {
			content
				.onAppear {
					openNewWindows()
					// A link about a radio whose window is hidden or closed opens it (W4).
					AccessoryManager.shared.appState?.windows.openWindowHandler = { window in
						openWindow(id: RadioWindows.radioWindowID, value: window)
					}
				}
				.onChange(of: connectedRadios) { _, _ in openNewWindows() }
				.onReceive(accessoryManager.radioDisconnectedByUser) { tracker.forgetOnceGone($0, connected: connectedRadios) }
				.onReceive(accessoryManager.radioRemoved) { tracker.forget($0) }
		} else {
			content
		}
	}

	private func openNewWindows() {
		for deviceId in tracker.toOpen(connected: connectedRadios) {
			openWindow(id: RadioWindows.radioWindowID, value: RadioWindow(deviceId: deviceId))
		}
	}
}

/// A radio's own window on the Mac: the whole app, for that radio (T310). It stays when the user
/// disconnects the radio, showing it off with Connect (W-02), and closes when they remove it;
/// closing it by hand only hides it (W-01). macOS brings back the windows open at quit.
struct RadioWindowRoot: View {
	let window: RadioWindow?
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.openWindow) private var openWindow
	@StateObject private var router = Router()
	/// This window's node filters: each window filters on its own.
	@StateObject private var nodeFilters = NodeFilterParameters()
	/// This window's radio, when Radios › Remove asks to remove it (D-18).
	@State private var radioToRemove: RadioToRemove?

	var body: some View {
		if let window, let deviceId = window.deviceId {
			ContentView(appState: appState, router: router)
#if targetEnvironment(macCatalyst)
				.background(ToolbarLayoutNudge())
#endif
				.modifier(WindowLockdownScope())
				.modifier(RadioWindowOpener(tracker: appState.radioWindowTracker))
				.focusedSceneValue(\.windowRadio, window)
				.focusedSceneValue(\.removeWindowRadio, removeAction(for: deviceId))
				.environmentObject(router)
				.environmentObject(nodeFilters)
				.environment(\.windowRadio, window)
				// Showing another radio opens its own window (W-13).
				.environment(\.selectWindowRadio, SelectWindowRadioAction { deviceId in
					openWindow(id: RadioWindows.radioWindowID, value: RadioWindow(deviceId: deviceId))
				})
				.navigationTitle(accessoryManager.radioName(of: deviceId) ?? "Meshtastic")
				.removeRadioConfirmation($radioToRemove)
				.onAppear { appState.radioWindowTracker.windowAppeared(deviceId) }
				.onDisappear { appState.radioWindowTracker.windowDisappeared(deviceId) }
				.onReceive(accessoryManager.radioRemoved) { removed in
					guard removed == deviceId else { return }
					// The last window open: the Connect window takes its place (T393).
					if appState.radioWindowTracker.closesLastWindow(deviceId, connectWindows: Self.connectWindowCount) {
						openWindow(id: RadioWindows.mainWindowID)
					}
					dismissWindow()
				}
		} else {
			Color.clear.onAppear { dismissWindow() }
		}
	}

	/// The Connect windows open, as `RadioWindowCommands.showConnectWindow()` finds them. The Mesh
	/// Map window doesn't count: it closes itself when it's the only window left.
	private static var connectWindowCount: Int {
		UIApplication.shared.connectedScenes.filter {
			$0.session.configuration.name == RadioWindows.mainWindowID && $0.activationState != .unattached
		}.count
	}

	/// Radios › Remove for this window's radio: once it has reported its node number, while it's
	/// connected with its connect done or it's one of the user's radios that's off (review V27-4,
	/// V27-5).
	private func removeAction(for deviceId: UUID) -> RemoveWindowRadioAction? {
		let num = accessoryManager.session(for: RadioWindow(deviceId: deviceId))?.nodeNum ?? accessoryManager.offlineRadio(deviceId)?.nodeNum
		guard let radioNum = num, accessoryManager.canRemoveRadio(radioNum) else {
			return nil
		}
		let name = accessoryManager.radioName(of: deviceId) ?? radioNum.toHex()
		return RemoveWindowRadioAction(name: name) {
			radioToRemove = RadioToRemove(nodeNum: radioNum, name: name)
		}
	}
}

#if targetEnvironment(macCatalyst)
/// After a radio window opens, macOS can pull it into a window tab group and resize it, and the
/// toolbar keeps the layout from its first size until the window lays out again: the Messages,
/// Nodes, Map, Settings and Connect control sits off centre until the sidebar is toggled. Once
/// the window has settled, it's made a point narrower and back, which makes it lay out again.
/// Once per window.
private struct ToolbarLayoutNudge: UIViewRepresentable {
	func makeUIView(context: Context) -> NudgeView { NudgeView() }
	func updateUIView(_ uiView: NudgeView, context: Context) {}

	final class NudgeView: UIView {
		private var hasNudged = false

		override func didMoveToWindow() {
			super.didMoveToWindow()
			guard !hasNudged, window != nil else { return }
			hasNudged = true
			isUserInteractionEnabled = false
			Task { @MainActor [weak self] in
				try? await Task.sleep(for: .milliseconds(800))
				await self?.nudge()
			}
		}

		private func nudge() async {
			guard let scene = window?.windowScene else { return }
			let frame = scene.effectiveGeometry.systemFrame
			guard frame.width > 1 else { return }
			var narrower = frame
			narrower.size.width -= 1
			scene.requestGeometryUpdate(.Mac(systemFrame: narrower)) { _ in }
			try? await Task.sleep(for: .milliseconds(50))
			scene.requestGeometryUpdate(.Mac(systemFrame: frame)) { _ in }
		}
	}
}
#endif

/// The Connect window on the Mac (W-02): the user's radios, connected or off, each opening its
/// own window, and the radios that can be added. Adding one opens its window once it's connected.
struct RadioListWindow: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@EnvironmentObject private var appState: AppState
	@ObservedObject private var manualConnections = ManualConnectionList.shared
	@Environment(\.openWindow) private var openWindow
	@Environment(\.dismissWindow) private var dismissWindow
	/// The radio windows on screen when this window opened. One that opens later, for a radio
	/// added or connected at launch, closes this window (`closeIfDone`); a radio reconnecting into
	/// its existing window doesn't.
	@State private var radioWindowsWhenOpened: Set<UUID> = []
	@State private var isSwitchingRadio = false
	@State private var isShowingDeviceOnboardingFlow = false
	/// A radio the user asked to remove; the list asks, so the dialog outlives the row.
	@State private var radioToRemove: RadioToRemove?
	/// Why a radio that's off didn't connect; its row is gone by then.
	@State private var connectError: String?

	/// Neither connected nor one of the user's radios that's off, which are listed above, nor one
	/// being removed.
	private var addableDevices: [Device] {
		let discovered = accessoryManager.devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		let manual = manualConnections.connectionsList.filter { saved in !discovered.contains { $0.id == saved.id } }
		let offline = Set(accessoryManager.offlineKnownRadios.map(\.deviceId))
		return (discovered + manual).filter {
			!accessoryManager.isRadioConnected($0.id) && !offline.contains($0.id) && !accessoryManager.deviceIdsBeingRemoved.contains($0.id)
		}
	}

	private func openRadioWindow(_ deviceId: UUID) {
		openWindow(id: RadioWindows.radioWindowID, value: RadioWindow(deviceId: deviceId))
	}

	/// The radios connected with their connect done, whose windows open (`RadioWindowOpener`).
	private var connectedRadioIDs: Set<UUID> {
		Set(accessoryManager.connectedRadios.map(\.id).filter { accessoryManager.linkStatus(of: $0).isConnected })
	}

	/// Nothing in this window waits for the user: first-launch setup, the Choose Radios sheet
	/// (W-15, which on the Mac shows here), a connect error or a Remove confirmation.
	private var isFree: Bool {
		!isShowingDeviceOnboardingFlow && radioToRemove == nil && connectError == nil
			&& accessoryManager.servicesNeedingRadio().isEmpty
	}

	/// Once a radio's window has opened since this window did, this one closes, as the Connect
	/// screen gives way once a radio is connected; Radios › Add Radio… brings it back (review
	/// V39). Not while something in it waits for the user; it closes when that's done. A moment
	/// after the connect, so the radio's window has opened.
	private func closeIfDone() {
		Task { @MainActor in
			try? await Task.sleep(for: .seconds(1))
			let opened = appState.radioWindowTracker.shownWindows.subtracting(radioWindowsWhenOpened)
			guard !opened.isEmpty, isFree else { return }
			dismissWindow()
		}
	}

	var body: some View {
		NavigationStack {
			List {
				if !accessoryManager.connectedRadios.isEmpty || !accessoryManager.offlineKnownRadios.isEmpty {
					Section(header: Text("Your Radios").font(.title)) {
						ForEach(accessoryManager.connectedRadios, id: \.id) { device in
							ConnectedRadioRow(device: device) {
								openRadioWindow(device.id)
							}
						}
						ForEach(accessoryManager.offlineKnownRadios) { radio in
							OfflineRadioRow(
								radio: radio,
								isSwitchingRadio: $isSwitchingRadio,
								open: { openRadioWindow(radio.deviceId) },
								connectFailed: { connectError = $0 }
							)
						}
					}
					.textCase(nil)
				}
				Section(header: HStack {
					Text("Add a Radio").font(.title)
					Spacer()
					ManualConnectionMenu(isSwitchingRadio: $isSwitchingRadio)
				}) {
					if accessoryManager.connectedRadioCount > 0, !accessoryManager.canConnectAnotherRadio {
						Text("You can connect up to \(AccessoryManager.maxConnectedRadios) radios at once. Disconnect one to add another.")
							.font(.callout)
							.foregroundStyle(.secondary)
					} else if addableDevices.isEmpty {
						Label("Looking for radios…", systemImage: "antenna.radiowaves.left.and.right")
							.font(.callout)
							.foregroundStyle(.secondary)
					}
					ForEach(addableDevices) { device in
						DeviceConnectRow(device: device, isSwitchingRadio: $isSwitchingRadio)
					}
				}
				.textCase(nil)
				// App-wide settings, reachable with no radio connected too.
				Section {
					NavigationLink {
						AppSettings()
					} label: {
						Label("App Settings", systemImage: "gearshape")
					}
				}
			}
			.navigationTitle("Radios")
			.removeRadioConfirmation($radioToRemove)
			.alert("Couldn't Connect", isPresented: Binding(get: { connectError != nil }, set: { if !$0 { connectError = nil } })) {
				Button("OK", role: .cancel) {}
			} message: {
				Text(connectError ?? "")
			}
		}
		.modifier(ServiceRadioChoiceGate())
		.onAppear {
			radioWindowsWhenOpened = appState.radioWindowTracker.shownWindows
			accessoryManager.startDiscovery()
			// The first-launch setup runs here on the Mac, as ContentView runs it elsewhere.
			if UserDefaults.firstLaunch && UIApplication.shared.isProtectedDataAvailable {
				isShowingDeviceOnboardingFlow = true
			}
		}
		.sheet(isPresented: $isShowingDeviceOnboardingFlow, onDismiss: {
			UserDefaults.firstLaunch = false
			accessoryManager.startDiscovery()
		}, content: {
			DeviceOnboarding()
		})
		// A connect stops discovery when it finishes; keep looking while this window is open.
		.onChange(of: accessoryManager.connectedRadioCount) { _, _ in accessoryManager.startDiscovery() }
		.onChange(of: connectedRadioIDs) { old, new in
			if !new.subtracting(old).isEmpty { closeIfDone() }
		}
		.onChange(of: isFree) { _, free in
			if free { closeIfDone() }
		}
		// Scanning is for this window: it stops with it, unless nothing is connected (review V39).
		.onDisappear { accessoryManager.stopDiscoveryWhenUnneeded() }
	}
}

/// A connected radio in the Connect window: its state, and Open, Disconnect and Remove.
private struct ConnectedRadioRow: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	/// Remove asks through the Connect window's confirmation, which outlives this row.
	@Environment(\.askToRemoveRadio) private var askToRemoveRadio
	let device: Device
	let open: () -> Void

	/// Its node number once it has reported it and its connect is done: what Remove removes
	/// (D-18). Not while it connects (review V27-5).
	private var removableRadioNum: Int64? {
		guard let num = device.num ?? accessoryManager.knownNodeNums[device.id], accessoryManager.canRemoveRadio(num) else { return nil }
		return num
	}

	var body: some View {
		let link = accessoryManager.linkStatus(of: device.id)
		let name = device.longName ?? device.name
		HStack(spacing: 12) {
			Image(systemName: link.isConnected ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right")
				.font(.title2)
				.foregroundStyle(link.isConnected ? Color.green : Color.orange)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(name)
					.font(.headline)
				HStack(spacing: 6) {
					TransportIcon(transportType: device.transportType)
					Text(link.isConnected ? "Connected" : "Connecting…")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				if let attention = link.attention {
					Label(attention.shortCaption, systemImage: attention.isLockdown ? "lock.fill" : "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			}
			Spacer()
			// Borderless, so each is its own click target: in a list row, buttons of the default
			// style make the row one target, and a click on Open ran Disconnect too.
			Button("Open", action: open)
				.buttonStyle(.borderless)
				.accessibilityLabel(Text("Open \(name)"))
			Button("Disconnect", role: .destructive) {
				Task { await accessoryManager.disconnectRadio(device.id) }
			}
			.buttonStyle(.borderless)
			.accessibilityLabel(Text("Disconnect \(name)"))
			if let askToRemoveRadio, let radioNum = removableRadioNum {
				Button("Remove", role: .destructive) {
					askToRemoveRadio(RadioToRemove(nodeNum: radioNum, name: name))
				}
				.buttonStyle(.borderless)
				.accessibilityLabel(Text("Remove \(name)"))
			}
		}
		.padding(.vertical, 4)
	}
}

/// Menu bar commands for the radio windows (T311–T313): a Radios menu with Add Radio…, Disconnect
/// and Remove for the key window's radio (W-07, D-18), and the user's radios, connected or off,
/// each of which opens its window, or brings it back when it was closed (W-01, W-02).
struct RadioWindowCommands: Commands {
	@ObservedObject var accessoryManager: AccessoryManager
	@Environment(\.openWindow) private var openWindow
	@FocusedValue(\.windowRadio) private var keyWindowRadio: RadioWindow?
	@FocusedValue(\.removeWindowRadio) private var removeKeyWindowRadio: RemoveWindowRadioAction?

	/// The key window's radio's name while it's connected: what Disconnect disconnects.
	private var keyRadioName: String? {
		guard let keyWindowRadio, keyWindowRadio.deviceId != nil else { return nil }
		let device = accessoryManager.session(for: keyWindowRadio)?.device
		return device.map { $0.longName ?? $0.name }
	}

	/// Brings the Connect window forward when it's open, else opens it: opening a window group by
	/// its id makes a new window each time. SwiftUI names each window's session after its group.
	private func showConnectWindow() {
		let open = UIApplication.shared.connectedScenes.first {
			$0.session.configuration.name == RadioWindows.mainWindowID && $0.activationState != .unattached
		}
		guard let open else {
			openWindow(id: RadioWindows.mainWindowID)
			return
		}
		if #available(iOS 17.0, *) {
			UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest(session: open.session))
		} else {
			UIApplication.shared.requestSceneSessionActivation(open.session, userActivity: nil, options: nil)
		}
	}

	var body: some Commands {
		// File › New Window would only open another Connect window on the Mac, so it goes there;
		// the iPad keeps it, as the way to open a second window.
		CommandGroup(replacing: .newItem) {
			if !RadioWindows.areEnabled {
				Button("New Window") {
					openWindow(id: RadioWindows.mainWindowID)
				}
				.keyboardShortcut("n")
			}
		}
		CommandMenu("Radios") {
			if RadioWindows.areEnabled {
				// Adding a radio is in the Connect window (W-02).
				Button("Add Radio…") {
					showConnectWindow()
				}
				.keyboardShortcut("n", modifiers: [.command, .shift])
				Divider()
				Button(keyRadioName.map { String.localizedStringWithFormat("Disconnect %@".localized, $0) } ?? "Disconnect".localized) {
					guard let deviceId = keyWindowRadio?.deviceId else { return }
					Task { await accessoryManager.disconnectRadio(deviceId) }
				}
				.disabled(keyRadioName == nil)
				Button(removeKeyWindowRadio.map { String.localizedStringWithFormat("Remove %@…".localized, $0.name) } ?? "Remove Radio…".localized) {
					removeKeyWindowRadio?.ask()
				}
				.disabled(removeKeyWindowRadio == nil)
				Divider()
				ForEach(accessoryManager.connectedRadios, id: \.id) { device in
					Button(device.longName ?? device.name) {
						openWindow(id: RadioWindows.radioWindowID, value: RadioWindow(deviceId: device.id))
					}
				}
				ForEach(accessoryManager.offlineKnownRadios) { radio in
					Button(String.localizedStringWithFormat("%@ (Not Connected)".localized, radio.name)) {
						openWindow(id: RadioWindows.radioWindowID, value: RadioWindow(deviceId: radio.deviceId))
					}
				}
			}
		}
	}
}

// MARK: - The key window's radio (W-07)

private struct WindowRadioFocusedKey: FocusedValueKey {
	typealias Value = RadioWindow
}

/// Radios › Remove for the key window's radio (D-18): its window asks first.
struct RemoveWindowRadioAction {
	let name: String
	let ask: () -> Void
}

private struct RemoveWindowRadioFocusedKey: FocusedValueKey {
	typealias Value = RemoveWindowRadioAction
}

extension FocusedValues {
	/// The radio of the key window, for menu bar commands.
	var windowRadio: RadioWindow? {
		get { self[WindowRadioFocusedKey.self] }
		set { self[WindowRadioFocusedKey.self] = newValue }
	}

	/// Removes the key window's radio, after asking; nil until it has reported its node number.
	var removeWindowRadio: RemoveWindowRadioAction? {
		get { self[RemoveWindowRadioFocusedKey.self] }
		set { self[RemoveWindowRadioFocusedKey.self] = newValue }
	}
}
