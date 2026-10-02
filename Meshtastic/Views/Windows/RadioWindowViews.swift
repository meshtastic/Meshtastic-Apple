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
/// radio (W-02) forgets it, so it opens again the next time it connects.
@MainActor
final class RadioWindowTracker {
	private(set) var opened: Set<UUID> = []

	nonisolated init() {}

	/// The radios among `connected` whose window should open now, and marks them opened.
	func toOpen(connected: Set<UUID>) -> [UUID] {
		let new = connected.subtracting(opened)
		opened.formUnion(new)
		return new.sorted { $0.uuidString < $1.uuidString }
	}

	/// `deviceId` was disconnected by the user: its window opens again when it's back.
	func forget(_ deviceId: UUID) {
		opened.remove(deviceId)
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
				.onReceive(accessoryManager.radioDisconnectedByUser) { tracker.forget($0) }
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

/// A radio's own window on the Mac: the whole app, for that radio (T310). Closes when the user
/// disconnects the radio (W-02); closing it by hand only hides it (W-01).
struct RadioWindowRoot: View {
	let window: RadioWindow?
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.openWindow) private var openWindow
	@StateObject private var router = Router()
	/// This window's node filters: each window filters on its own.
	@StateObject private var nodeFilters = NodeFilterParameters()

	var body: some View {
		if let window, window.deviceId != nil {
			ContentView(appState: appState, router: router)
#if targetEnvironment(macCatalyst)
				.background(ToolbarLayoutNudge())
#endif
				.modifier(WindowLockdownScope())
				.modifier(RadioWindowOpener(tracker: appState.radioWindowTracker))
				.focusedSceneValue(\.windowRadio, window)
				.environmentObject(router)
				.environmentObject(nodeFilters)
				.environment(\.windowRadio, window)
				// Showing another radio opens its own window (W-13).
				.environment(\.selectWindowRadio, SelectWindowRadioAction { deviceId in
					openWindow(id: RadioWindows.radioWindowID, value: RadioWindow(deviceId: deviceId))
				})
				.navigationTitle(title(for: window))
				.onReceive(accessoryManager.radioDisconnectedByUser) { deviceId in
					if deviceId == window.deviceId {
						dismissWindow()
					}
				}
		} else {
			Color.clear.onAppear { dismissWindow() }
		}
	}

	private func title(for window: RadioWindow) -> String {
		guard let device = accessoryManager.session(for: window)?.device ?? accessoryManager.devices.first(where: { $0.id == window.deviceId }) else {
			return "Meshtastic"
		}
		return device.longName ?? device.name
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

/// The Connect window on the Mac (W-02): the connected radios, each opening its own window,
/// and the radios that can be added. Adding one opens its window once it's connected.
struct RadioListWindow: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@ObservedObject private var manualConnections = ManualConnectionList.shared
	@Environment(\.openWindow) private var openWindow
	@State private var isSwitchingRadio = false
	@State private var isShowingDeviceOnboardingFlow = false

	private var addableDevices: [Device] {
		let discovered = accessoryManager.devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		let manual = manualConnections.connectionsList.filter { saved in !discovered.contains { $0.id == saved.id } }
		return (discovered + manual).filter { !accessoryManager.isRadioConnected($0.id) }
	}

	var body: some View {
		NavigationStack {
			List {
				if !accessoryManager.connectedRadios.isEmpty {
					Section(header: Text("Connected Radios").font(.title)) {
						ForEach(accessoryManager.connectedRadios, id: \.id) { device in
							ConnectedRadioRow(device: device) {
								openWindow(id: RadioWindows.radioWindowID, value: RadioWindow(deviceId: device.id))
							}
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
		}
		.modifier(ServiceRadioChoiceGate())
		.onAppear {
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
	}
}

/// A connected radio in the Connect window: its state, and Open and Disconnect.
private struct ConnectedRadioRow: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let device: Device
	let open: () -> Void

	var body: some View {
		let link = accessoryManager.linkStatus(of: device.id)
		HStack(spacing: 12) {
			Image(systemName: link.isConnected ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right")
				.font(.title2)
				.foregroundStyle(link.isConnected ? Color.green : Color.orange)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(device.longName ?? device.name)
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
			Button("Disconnect", role: .destructive) {
				Task { await accessoryManager.disconnectRadio(device.id) }
			}
			.buttonStyle(.borderless)
		}
		.padding(.vertical, 4)
	}
}

/// Menu bar commands for the radio windows (T311–T313): a Radios menu with Add Radio…, Disconnect
/// for the key window's radio (W-07) and the connected radios, each of which reopens its window
/// when it was closed (W-01).
struct RadioWindowCommands: Commands {
	@ObservedObject var accessoryManager: AccessoryManager
	@Environment(\.openWindow) private var openWindow
	@FocusedValue(\.windowRadio) private var keyWindowRadio: RadioWindow?

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
				Divider()
				ForEach(accessoryManager.connectedRadios, id: \.id) { device in
					Button(device.longName ?? device.name) {
						openWindow(id: RadioWindows.radioWindowID, value: RadioWindow(deviceId: device.id))
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

extension FocusedValues {
	/// The radio of the key window, for menu bar commands.
	var windowRadio: RadioWindow? {
		get { self[WindowRadioFocusedKey.self] }
		set { self[WindowRadioFocusedKey.self] = newValue }
	}
}
