//
//  CinemaScreen.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
#if os(visionOS)
import Combine
import SwiftData
import SwiftUI
import UIKit

/// The app sections the cinema's front screen shows, one at a time, in the app's tab bar order.
enum CinemaSection: String, CaseIterable, Identifiable {
	case messages, nodes, map, settings, connect

	var id: String { rawValue }

	/// The app tab this section stands for, so work the views only do on their own tab runs.
	var tab: NavigationState.Tab {
		switch self {
		case .messages: .messages
		case .nodes: .nodes
		case .map: .map
		case .settings: .settings
		case .connect: .connect
		}
	}

	var title: String {
		switch self {
		case .messages: String(localized: "Messages")
		case .nodes: String(localized: "Nodes")
		case .map: String(localized: "Map")
		case .settings: String(localized: "Settings")
		case .connect: String(localized: "Connect")
		}
	}

	/// The tab bar's icons.
	var icon: Image {
		switch self {
		case .messages: Image(systemName: "message")
		case .nodes: Image("custom.mesh.radio")
		case .map: Image(systemName: "map")
		case .settings: Image(systemName: "gear")
		case .connect: Image(systemName: "link")
		}
	}
}

/// The front screen's state. The space keeps it, outside the screen's attachment, so a database
/// reset or a rebuilt attachment doesn't lose where each section was.
@MainActor
final class CinemaScreenModel: ObservableObject {
	@Published var section: CinemaSection = .connect {
		didSet {
			// A page pushed over the old section would hide the new one.
			if oldValue != section { presenter.popAll() }
		}
	}
	/// Each section's own navigation, with its tab selected.
	let routers: [CinemaSection: Router]
	let filters: [CinemaSection: NodeFilterParameters]
	/// The pages and banners the sections' sheets and dialogs become on the screen.
	let presenter = PanelPresenter()
	private var tokens: [UUID] = []
	private var cancellables: Set<AnyCancellable> = []

	init() {
		routers = Dictionary(uniqueKeysWithValues: CinemaSection.allCases.map {
			($0, Router(navigationState: NavigationState(selectedTab: $0.tab)))
		})
		filters = Dictionary(uniqueKeysWithValues: CinemaSection.allCases.map { ($0, NodeFilterParameters()) })
		// The screens switch tabs through their router, like Node Detail's Estimate Coverage or a
		// message's mention. Each section has its own router, so the switch and where it was going
		// are passed on to the section that shows it, once the screen has set both.
		for (section, router) in routers {
			router.$selectedTab
				.dropFirst()
				.filter { $0 != section.tab }
				.receive(on: DispatchQueue.main)
				.sink { [weak self] _ in
					MainActor.assumeIsolated { self?.forwardTabSwitch(from: section) }
				}
				.store(in: &cancellables)
		}
		#if DEBUG
		// Simulator screenshots: `--meshtastic-cinema-section <name>` starts on that section.
		let arguments = ProcessInfo.processInfo.arguments
		if let index = arguments.firstIndex(of: "--meshtastic-cinema-section"), arguments.indices.contains(index + 1),
		   let section = CinemaSection(rawValue: arguments[index + 1]) {
			self.section = section
		}
		#endif
	}

	func router(for section: CinemaSection) -> Router {
		routers[section] ?? Router()
	}

	func filters(for section: CinemaSection) -> NodeFilterParameters {
		filters[section] ?? NodeFilterParameters()
	}

	/// Shows what a tap on one of the tent's boards asked for.
	func show(_ request: CinemaScreenRequest) {
		switch request {
		case .node(let nodeNum):
			presenter.popAll()
			section = .nodes
			router(for: .nodes).navigateToNodeDetail(nodeNum: nodeNum)
		case .coverageEstimate(let nodeNum):
			presenter.popAll()
			section = .map
			router(for: .map).mapState = .coverageEstimate(nodeNum)
		case .traceRoute(let routeId):
			// The map looks the route up and frames it, as for the widget's deep link.
			presenter.popAll()
			section = .map
			router(for: .map).mapState = .traceRoute(routeId)
		}
	}

	/// Moves a tab switch made in one section's router to the section for that tab, with the
	/// state the screen set for it, and puts the first router back on its own tab.
	func forwardTabSwitch(from source: CinemaSection) {
		let from = router(for: source)
		let tab = from.selectedTab
		guard tab != source.tab else { return }
		from.selectedTab = source.tab
		guard let target = CinemaSection.allCases.first(where: { $0.tab == tab }) else { return }
		let to = router(for: target)
		switch target {
		case .messages:
			to.messagesState = from.messagesState
			to.messagesSection = from.messagesSection
			from.messagesState = nil
			from.messagesSection = nil
		case .nodes:
			to.selectedNodeNum = from.selectedNodeNum
		case .map:
			to.mapState = from.mapState
			from.mapState = nil
		case .settings:
			to.settingsPath = from.settingsPath
			from.settingsPath = []
		case .connect:
			break
		}
		section = target
	}

	/// Registers the routers and the page stack with the app's windows, so switching radios pops
	/// them too.
	func register(with sceneRouters: SceneRouters) {
		guard tokens.isEmpty else { return }
		tokens = routers.values.map { sceneRouters.register($0) }
		tokens.append(sceneRouters.register(stack: { [presenter] in presenter.popAll() }))
	}

	func unregister(from sceneRouters: SceneRouters) {
		tokens.forEach { sceneRouters.unregister($0) }
		tokens = []
	}
}

/// The big screen on the cinema's front wall: one app section at a time, with the store and the
/// radio like the app window. The screen is a panel host, since an immersive space never shows a
/// sheet or an alert: the sections' sheets and dialogs become pages pushed over the screen and
/// their alerts a banner at its top. The host goes around the whole screen, with the store, the
/// radio and the section's navigation outside it, so a pushed page has them too.
struct CinemaScreen: View {
	/// The screen's size in points. The front wall's anchor has the same shape.
	static let size = CGSize(width: 1500, height: 940)
	static let cornerRadius: CGFloat = 48

	let container: ModelContainer
	@ObservedObject var model: CinemaScreenModel
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@EnvironmentObject private var lockdown: LockdownCoordinator

	var body: some View {
		let section = model.section
		let router = model.router(for: section)
		let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
		let gated = lockdown.isBlockingSession || accessoryManager.firmwareUpdateRequired
		// The tint goes around the host, so pages and banners get it like the section.
		EventFirmwareTintScope {
			Group {
				if gated {
					// The lockdown and firmware gates are full screen covers, which only a window can show.
					CinemaScreenGate()
				} else {
					content(for: section, router: router)
						.trackScreen(section.tab.screenName)
						.id(section)
				}
			}
			.id(appState.databaseResetID)
			.panelPresentationHost(model.presenter)
			// The pages are the model's and outlive the gate: one up when the gate goes up would
			// stay over it, and come back when it drops.
			.onChange(of: gated) { _, gated in
				if gated { model.presenter.popAll() }
			}
		}
		.frame(width: Self.size.width, height: Self.size.height)
		.clipShape(shape)
		.glassBackgroundEffect(in: shape)
		.modelContainer(container)
		.environmentObject(appState)
		.environmentObject(accessoryManager)
		.environmentObject(lockdown)
		.environmentObject(router)
		.environmentObject(model.filters(for: section))
		.environmentObject(MeshtasticAPI.shared)
	}

	@ViewBuilder
	private func content(for section: CinemaSection, router: Router) -> some View {
		switch section {
		case .messages:
			Messages(
				router: router,
				unreadChannelMessages: $appState.unreadChannelMessages,
				unreadDirectMessages: $appState.unreadDirectMessages
			)
		case .nodes:
			NodeList()
		case .map:
			MeshMapMK(router: router, showOpenWindowButton: false)
		case .settings:
			Settings()
		case .connect:
			Connect(router: router)
		}
	}
}

/// Shown on the screen while the radio needs something only the app window can ask for.
private struct CinemaScreenGate: View {
	@Environment(\.openWindow) private var openWindow
	@EnvironmentObject private var appState: AppState

	var body: some View {
		VStack(spacing: 24) {
			Image(systemName: "macwindow")
				.font(.system(size: 64))
				.foregroundStyle(.secondary)
			Text("Continue in the app window", comment: "Cinema: the front screen while the radio is locked or needs a firmware update, which only the app window can handle")
				.font(.title)
			Button {
				CinemaScene.reopenMainWindow(openWindow, appState: appState)
			} label: {
				Label(String(localized: "Open App Window", comment: "Cinema: opens the app's main window from the immersive cinema"), systemImage: "macwindow")
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

/// The section picker above the front screen.
struct CinemaTabStrip: View {
	@ObservedObject var model: CinemaScreenModel

	/// A segment shows either text or one image, and drops images inside text, so each segment is
	/// the icon and title drawn into one template image that the control tints like its text.
	@MainActor private static var segments: [CinemaSection: Image] = [:]

	@MainActor private static func segment(_ section: CinemaSection) -> Image {
		if let image = segments[section] { return image }
		let renderer = ImageRenderer(content: HStack(spacing: 6) { section.icon; Text(section.title) }
			.font(.system(size: 17, weight: .semibold))
			.foregroundStyle(.black))
		renderer.scale = 3
		guard let rendered = renderer.uiImage else { return section.icon }
		let image = Image(uiImage: rendered.withRenderingMode(.alwaysTemplate))
		segments[section] = image
		return image
	}

	var body: some View {
		// The system segmented control draws the one selection highlight.
		Picker(String(localized: "Section", comment: "Cinema: the picker above the front screen that picks the app section it shows"), selection: $model.section) {
			ForEach(CinemaSection.allCases) { section in
				Self.segment(section)
					.accessibilityLabel(section.title)
					.tag(section)
			}
		}
		.pickerStyle(.segmented)
		.labelsHidden()
		.frame(width: 900)
		.padding(10)
		.glassBackgroundEffect()
	}
}
#endif
