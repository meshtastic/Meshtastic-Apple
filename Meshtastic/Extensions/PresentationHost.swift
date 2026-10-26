//
//  PresentationHost.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//

import SwiftUI

/// Where a screen is shown. In a window, sheets, alerts and confirmation dialogs work as usual.
/// On a fixed panel inside the visionOS cinema tent (an immersive space) none of them ever
/// appear, and one attached to a NavigationStack's root content draws the whole stack blank.
/// The `hosted…` modifiers below call the normal SwiftUI modifier in a window. In a panel they
/// show the same content another way: sheets, confirmations and text field alerts become pages
/// pushed over the screen, info alerts become a banner at the top of the panel.
enum PresentationHost: Sendable {
	case window
	case panel
}

extension EnvironmentValues {
	@Entry var presentationHost: PresentationHost = .window
	/// Set by `panelPresentationHost()`; shows the pages and banners raised inside the panel.
	@Entry var panelPresenter: PanelPresenter?
}

// MARK: - Panel host

extension View {
	/// Marks this view as a panel and adds the page stack and banner area that the hosted
	/// modifiers show in. Apply it once, around the whole panel, outside the screen's own
	/// NavigationStack. A panel that changes what it shows, like the cinema screen switching
	/// sections, passes its own presenter so it can pop the pages itself.
	///
	/// The pages go on a stack of their own rather than the screen's: a navigation destination
	/// inside a List row or a split view's sidebar never pushes, and most of these presentations
	/// sit in one of those.
	func panelPresentationHost(_ presenter: PanelPresenter? = nil) -> some View {
		modifier(PanelPresentationHostModifier(shared: presenter))
	}
}

private struct PanelPresentationHostModifier: ViewModifier {
	/// The panel's own presenter, when it keeps one.
	let shared: PanelPresenter?
	@State private var owned = PanelPresenter()

	func body(content: Content) -> some View {
		let presenter = shared ?? owned
		let showingPage = !presenter.pages.isEmpty
		ZStack {
			content
				.opacity(showingPage ? 0 : 1)
				.accessibilityHidden(showingPage)
			// Always there so the first page slides in like a push. Its root is empty, so every
			// page is pushed and has a back button, and dismiss() inside a page pops it.
			NavigationStack(path: Binding(get: { presenter.path }, set: { presenter.path = $0 })) {
				Color.clear
					.toolbar(.hidden, for: .navigationBar)
					.navigationDestination(for: UUID.self) { id in
						presenter.page(id)
					}
			}
			.opacity(showingPage ? 1 : 0)
			.allowsHitTesting(showingPage)
			.accessibilityHidden(!showingPage)
		}
		.environment(\.presentationHost, .panel)
		.environment(\.panelPresenter, presenter)
		.overlay(alignment: .top) {
			if let banner = presenter.banner {
				PanelBannerCard(banner: banner)
					.id(banner.id)
					.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.default, value: presenter.banner?.id)
	}
}

/// The pages and the alert banner a panel is showing.
@MainActor @Observable
final class PanelPresenter {
	struct Page {
		let id: UUID
		let content: PanelPageContent
		/// Clears the presenting modifier's own isPresented binding or item.
		let onPop: () -> Void
	}

	struct Banner: Identifiable {
		let id: UUID
		let title: Text
		let message: AnyView
		let actions: AnyView
		/// Clears the alert's own isPresented binding.
		let dismiss: () -> Void
	}

	private(set) var pages: [Page] = []
	/// One banner at a time; a new one replaces the old.
	private(set) var banner: Banner?

	/// The page stack's path. A pop from the back button lands here.
	var path: [UUID] {
		get { pages.map(\.id) }
		set {
			let popped = pages.filter { !newValue.contains($0.id) }
			pages.removeAll { !newValue.contains($0.id) }
			popped.reversed().forEach { $0.onPop() }
		}
	}

	func page(_ id: UUID) -> AnyView? {
		pages.first { $0.id == id }.map { AnyView(PanelPageView(content: $0.content)) }
	}

	/// Pushes a page, or replaces its content when it is already showing.
	func push(id: UUID, content: AnyView, onPop: @escaping () -> Void) {
		if !update(id: id, content: content) {
			pages.append(Page(id: id, content: PanelPageContent(content), onPop: onPop))
		}
	}

	/// Replaces a showing page's content, without touching the stack. Returns false when the page
	/// isn't showing.
	@discardableResult
	func update(id: UUID, content: AnyView) -> Bool {
		guard let page = pages.first(where: { $0.id == id }) else { return false }
		page.content.view = content
		return true
	}

	/// Pops a page and any pages pushed from it.
	func pop(id: UUID) {
		guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
		let popped = pages[index...]
		pages.removeSubrange(index...)
		popped.reversed().forEach { $0.onPop() }
	}

	/// Pops every page and drops the banner, clearing their presenting views' flags: the panel
	/// is about to show something else.
	func popAll() {
		let popped = pages
		pages.removeAll()
		popped.reversed().forEach { $0.onPop() }
		if let banner {
			self.banner = nil
			banner.dismiss()
		}
	}

	func show(_ banner: Banner) {
		if let current = self.banner, current.id != banner.id { current.dismiss() }
		self.banner = banner
	}

	func removeBanner(id: UUID) {
		if banner?.id == id { banner = nil }
	}
}

/// What a pushed page shows. A sheet's content is rebuilt each time the view presenting it
/// updates; the presenting modifier does the same by replacing this, so the page follows the
/// state it was built from (a button enabled once a text field has text, a list of results).
@MainActor @Observable
final class PanelPageContent {
	var view: AnyView

	init(_ view: AnyView) {
		self.view = view
	}
}

private struct PanelPageView: View {
	let content: PanelPageContent

	var body: some View {
		content.view
	}
}

// MARK: - Sheets and full screen covers

extension View {
	/// `.sheet(isPresented:)` in a window; a pushed page in a panel.
	func hostedSheet<Sheet: View>(
		isPresented: Binding<Bool>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping () -> Sheet
	) -> some View {
		modifier(HostedFlagPresentation(style: .sheet, isPresented: isPresented, onDismiss: onDismiss, page: content))
	}

	/// `.sheet(item:)` in a window; a pushed page in a panel.
	func hostedSheet<Item: Identifiable, Sheet: View>(
		item: Binding<Item?>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping (Item) -> Sheet
	) -> some View {
		modifier(HostedItemPresentation(style: .sheet, item: item, onDismiss: onDismiss, page: content))
	}

	/// `.fullScreenCover(isPresented:)` in a window; a push in a panel.
	func hostedFullScreenCover<Cover: View>(
		isPresented: Binding<Bool>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping () -> Cover
	) -> some View {
		modifier(HostedFlagPresentation(style: .fullScreenCover, isPresented: isPresented, onDismiss: onDismiss, page: content))
	}

	/// `.fullScreenCover(item:)` in a window; a push in a panel.
	func hostedFullScreenCover<Item: Identifiable, Cover: View>(
		item: Binding<Item?>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping (Item) -> Cover
	) -> some View {
		modifier(HostedItemPresentation(style: .fullScreenCover, item: item, onDismiss: onDismiss, page: content))
	}
}

private enum HostedPresentationStyle {
	case sheet, fullScreenCover, popover
}

private struct HostedFlagPresentation<Page: View>: ViewModifier {
	let style: HostedPresentationStyle
	@Binding var isPresented: Bool
	let onDismiss: (() -> Void)?
	let page: () -> Page
	@Environment(\.presentationHost) private var host

	func body(content: Content) -> some View {
		switch (host, style) {
		case (.window, .sheet):
			content.sheet(isPresented: $isPresented, onDismiss: onDismiss, content: page)
		case (.window, .fullScreenCover):
			content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss, content: page)
		case (.window, .popover):
			content.popover(isPresented: $isPresented, content: page)
		case (.panel, _):
			content.modifier(PanelPush(isPresented: $isPresented, onDismiss: onDismiss, page: page))
		}
	}
}

private struct HostedItemPresentation<Item: Identifiable, Page: View>: ViewModifier {
	let style: HostedPresentationStyle
	@Binding var item: Item?
	let onDismiss: (() -> Void)?
	let page: (Item) -> Page
	@Environment(\.presentationHost) private var host
	/// The last item shown, so the pushed page keeps its content while it slides away.
	@State private var shown: Item?

	func body(content: Content) -> some View {
		switch (host, style) {
		case (.window, .sheet):
			content.sheet(item: $item, onDismiss: onDismiss, content: page)
		case (.window, .fullScreenCover):
			content.fullScreenCover(item: $item, onDismiss: onDismiss, content: page)
		case (.window, .popover):
			content.popover(item: $item, content: page)
		case (.panel, _):
			content
				.modifier(PanelPush(
					isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
					onDismiss: onDismiss,
					contentID: item.map { AnyHashable($0.id) }
				) {
					if let value = item ?? shown { page(value) }
				})
				.onChange(of: item?.id) {
					if let item { shown = item }
				}
		}
	}
}

/// Shows `page` while `isPresented` is true and calls `onDismiss` once it is gone. With a panel
/// host above, the page goes on the host's page stack; without one (a preview, or a panel that
/// forgot the host) it falls back to a push on the enclosing NavigationStack.
private struct PanelPush<Page: View>: ViewModifier {
	@Binding var isPresented: Bool
	let onDismiss: (() -> Void)?
	/// Changes when the page should be rebuilt while it is showing, like a sheet's new item.
	var contentID: AnyHashable?
	@ViewBuilder let page: () -> Page
	@Environment(\.panelPresenter) private var presenter
	@State private var pageID = UUID()

	func body(content: Content) -> some View {
		// This runs whenever the presenting view updates, so a showing page gets the new content.
		if let presenter, isPresented {
			// swiftlint:disable:next redundant_discardable_let
			let _ = presenter.update(id: pageID, content: AnyView(page()))
		}
		Group {
			if let presenter {
				content
					.onChange(of: isPresented, initial: true) { _, shown in
						if shown { push(on: presenter) } else { presenter.pop(id: pageID) }
					}
					.onChange(of: contentID) {
						if isPresented { push(on: presenter) }
					}
			} else {
				content.navigationDestination(isPresented: $isPresented, destination: page)
			}
		}
		.onChange(of: isPresented) { old, new in
			if old, !new { onDismiss?() }
		}
	}

	private func push(on presenter: PanelPresenter) {
		let binding = $isPresented
		presenter.push(id: pageID, content: AnyView(page())) {
			binding.wrappedValue = false
		}
	}
}

// MARK: - Popovers

extension View {
	/// `.popover(isPresented:)` in a window; a pushed page in a panel.
	func hostedPopover<Popover: View>(
		isPresented: Binding<Bool>,
		@ViewBuilder content: @escaping () -> Popover
	) -> some View {
		modifier(HostedPopover(isPresented: isPresented, anchor: nil, arrowEdge: nil, page: content))
	}

	/// `.popover(isPresented:attachmentAnchor:arrowEdge:)` in a window; a pushed page in a panel.
	func hostedPopover<Popover: View>(
		isPresented: Binding<Bool>,
		attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
		arrowEdge: Edge,
		@ViewBuilder content: @escaping () -> Popover
	) -> some View {
		modifier(HostedPopover(isPresented: isPresented, anchor: attachmentAnchor, arrowEdge: arrowEdge, page: content))
	}

	/// `.popover(item:)` in a window; a pushed page in a panel.
	func hostedPopover<Item: Identifiable, Popover: View>(
		item: Binding<Item?>,
		@ViewBuilder content: @escaping (Item) -> Popover
	) -> some View {
		modifier(HostedItemPresentation(style: .popover, item: item, onDismiss: nil, page: content))
	}
}

private struct HostedPopover<Popover: View>: ViewModifier {
	@Binding var isPresented: Bool
	let anchor: PopoverAttachmentAnchor?
	let arrowEdge: Edge?
	let page: () -> Popover
	@Environment(\.presentationHost) private var host

	func body(content: Content) -> some View {
		switch host {
		case .window:
			if let arrowEdge {
				content.popover(isPresented: $isPresented, attachmentAnchor: anchor ?? .rect(.bounds), arrowEdge: arrowEdge, content: page)
			} else {
				content.popover(isPresented: $isPresented, content: page)
			}
		case .panel:
			content.modifier(PanelPush(isPresented: $isPresented, onDismiss: nil, page: page))
		}
	}
}

// MARK: - Confirmation dialogs

extension View {
	/// `.confirmationDialog` in a window. In a panel, a pushed page with the title, the message,
	/// the same buttons full width, and Cancel; any button pops it.
	func hostedConfirmation<Actions: View, Message: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: @escaping () -> Actions,
		@ViewBuilder message: @escaping () -> Message
	) -> some View {
		hostedConfirmation(Text(titleKey), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message)
	}

	func hostedConfirmation<Actions: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: @escaping () -> Actions
	) -> some View {
		hostedConfirmation(Text(titleKey), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
	}

	@_disfavoredOverload
	func hostedConfirmation<S: StringProtocol, Actions: View, Message: View>(
		_ title: S,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: @escaping () -> Actions,
		@ViewBuilder message: @escaping () -> Message
	) -> some View {
		hostedConfirmation(Text(title), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message)
	}

	@_disfavoredOverload
	func hostedConfirmation<S: StringProtocol, Actions: View>(
		_ title: S,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: @escaping () -> Actions
	) -> some View {
		hostedConfirmation(Text(title), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
	}

	func hostedConfirmation<Actions: View>(
		_ title: Text,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: @escaping () -> Actions
	) -> some View {
		hostedConfirmation(title, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
	}

	func hostedConfirmation<Actions: View, Message: View>(
		_ title: Text,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: @escaping () -> Actions,
		@ViewBuilder message: @escaping () -> Message
	) -> some View {
		modifier(HostedConfirmation(
			title: title,
			isPresented: isPresented,
			titleVisibility: titleVisibility,
			actions: actions,
			message: message
		))
	}

	/// `.confirmationDialog(presenting:)` in a window; the pushed confirm page in a panel.
	func hostedConfirmation<T, Actions: View, Message: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		presenting data: T?,
		@ViewBuilder actions: @escaping (T) -> Actions,
		@ViewBuilder message: @escaping (T) -> Message
	) -> some View {
		modifier(HostedPresentingDialog(
			kind: .confirmation(titleVisibility),
			title: Text(titleKey),
			isPresented: isPresented,
			data: data,
			actions: actions,
			message: message
		))
	}
}

private struct HostedConfirmation<Actions: View, Message: View>: ViewModifier {
	let title: Text
	@Binding var isPresented: Bool
	let titleVisibility: Visibility
	let actions: () -> Actions
	let message: () -> Message
	@Environment(\.presentationHost) private var host

	func body(content: Content) -> some View {
		switch host {
		case .window:
			content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: titleVisibility, actions: actions, message: message)
		case .panel:
			content.modifier(PanelPush(isPresented: $isPresented, onDismiss: nil) {
				PanelDialogPage(
					title: titleVisibility == .hidden ? nil : title,
					message: message(),
					actions: actions(),
					close: { isPresented = false }
				)
			})
		}
	}
}

// MARK: - Alerts

extension View {
	/// `.alert` in a window. In a panel, a banner at the top of the panel with the title, message
	/// and buttons; any button closes it. For alerts with a text field use `hostedFormAlert`.
	func hostedAlert<Actions: View, Message: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: @escaping () -> Actions,
		@ViewBuilder message: @escaping () -> Message
	) -> some View {
		hostedAlert(Text(titleKey), isPresented: isPresented, actions: actions, message: message)
	}

	func hostedAlert<Actions: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: @escaping () -> Actions
	) -> some View {
		hostedAlert(Text(titleKey), isPresented: isPresented, actions: actions) { EmptyView() }
	}

	@_disfavoredOverload
	func hostedAlert<S: StringProtocol, Actions: View, Message: View>(
		_ title: S,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: @escaping () -> Actions,
		@ViewBuilder message: @escaping () -> Message
	) -> some View {
		hostedAlert(Text(title), isPresented: isPresented, actions: actions, message: message)
	}

	@_disfavoredOverload
	func hostedAlert<S: StringProtocol, Actions: View>(
		_ title: S,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: @escaping () -> Actions
	) -> some View {
		hostedAlert(Text(title), isPresented: isPresented, actions: actions) { EmptyView() }
	}

	func hostedAlert<Actions: View>(
		_ title: Text,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: @escaping () -> Actions
	) -> some View {
		hostedAlert(title, isPresented: isPresented, actions: actions) { EmptyView() }
	}

	func hostedAlert<Actions: View, Message: View>(
		_ title: Text,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: @escaping () -> Actions,
		@ViewBuilder message: @escaping () -> Message
	) -> some View {
		modifier(HostedAlert(title: title, isPresented: isPresented, actions: actions, message: message))
	}

	/// `.alert(presenting:)` in a window; the banner in a panel.
	func hostedAlert<T, Actions: View, Message: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		presenting data: T?,
		@ViewBuilder actions: @escaping (T) -> Actions,
		@ViewBuilder message: @escaping (T) -> Message
	) -> some View {
		modifier(HostedPresentingDialog(
			kind: .alert,
			title: Text(titleKey),
			isPresented: isPresented,
			data: data,
			actions: actions,
			message: message
		))
	}

	/// `.alert` with a text field in a window. In a panel, a small pushed page with the field
	/// and the buttons; any button pops it.
	func hostedFormAlert<Actions: View, Message: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: @escaping () -> Actions,
		@ViewBuilder message: @escaping () -> Message
	) -> some View {
		modifier(HostedFormAlert(title: Text(titleKey), isPresented: isPresented, actions: actions, message: message))
	}

	func hostedFormAlert<Actions: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: @escaping () -> Actions
	) -> some View {
		modifier(HostedFormAlert(title: Text(titleKey), isPresented: isPresented, actions: actions) { EmptyView() })
	}

	func hostedFormAlert<T, Actions: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		presenting data: T?,
		@ViewBuilder actions: @escaping (T) -> Actions
	) -> some View {
		hostedFormAlert(titleKey, isPresented: isPresented, presenting: data, actions: actions) { _ in EmptyView() }
	}

	func hostedAlert<T, Actions: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		presenting data: T?,
		@ViewBuilder actions: @escaping (T) -> Actions
	) -> some View {
		hostedAlert(titleKey, isPresented: isPresented, presenting: data, actions: actions) { _ in EmptyView() }
	}

	/// `.alert(presenting:)` with a text field; the pushed form page in a panel.
	func hostedFormAlert<T, Actions: View, Message: View>(
		_ titleKey: LocalizedStringKey,
		isPresented: Binding<Bool>,
		presenting data: T?,
		@ViewBuilder actions: @escaping (T) -> Actions,
		@ViewBuilder message: @escaping (T) -> Message
	) -> some View {
		modifier(HostedPresentingDialog(
			kind: .formAlert,
			title: Text(titleKey),
			isPresented: isPresented,
			data: data,
			actions: actions,
			message: message
		))
	}
}

private struct HostedAlert<Actions: View, Message: View>: ViewModifier {
	let title: Text
	@Binding var isPresented: Bool
	let actions: () -> Actions
	let message: () -> Message
	@Environment(\.presentationHost) private var host
	@Environment(\.panelPresenter) private var presenter
	@State private var bannerID = UUID()

	func body(content: Content) -> some View {
		switch host {
		case .window:
			content.alert(title, isPresented: $isPresented, actions: actions, message: message)
		case .panel:
			if let presenter {
				content
					.onChange(of: isPresented, initial: true) { _, shown in
						if shown {
							presenter.show(banner)
						} else {
							presenter.removeBanner(id: bannerID)
						}
					}
			} else {
				// No panel host above: show the banner over this view instead.
				content.overlay(alignment: .top) {
					if isPresented { PanelBannerCard(banner: banner) }
				}
			}
		}
	}

	private var banner: PanelPresenter.Banner {
		let binding = $isPresented
		return PanelPresenter.Banner(
			id: bannerID,
			title: title,
			message: AnyView(message()),
			actions: AnyView(actions()),
			dismiss: { binding.wrappedValue = false }
		)
	}
}

private struct HostedFormAlert<Actions: View, Message: View>: ViewModifier {
	let title: Text
	@Binding var isPresented: Bool
	let actions: () -> Actions
	let message: () -> Message
	@Environment(\.presentationHost) private var host

	func body(content: Content) -> some View {
		switch host {
		case .window:
			content.alert(title, isPresented: $isPresented, actions: actions, message: message)
		case .panel:
			content.modifier(PanelPush(isPresented: $isPresented, onDismiss: nil) {
				PanelDialogPage(title: title, message: message(), actions: actions(), close: { isPresented = false })
			})
		}
	}
}

// MARK: - Window-only views

extension View {
	/// Shows the view as is in a window. In a panel, where it can't work (share sheets, file
	/// pickers, links into other apps), shows an "Open in App Window" button in its place.
	func hostedWindowOnly() -> some View {
		modifier(WindowOnly())
	}
}

private struct WindowOnly: ViewModifier {
	@Environment(\.presentationHost) private var host

	func body(content: Content) -> some View {
		switch host {
		case .window: content
		case .panel: OpenInAppWindowButton()
		}
	}
}

/// Opens the main window, or brings the open one forward rather than opening another. Always
/// there: it stands in for a control, which shouldn't vanish once a window is open.
private struct OpenInAppWindowButton: View {
	@EnvironmentObject private var appState: AppState
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		Button {
			if appState.mainWindowCount > 0 {
				appState.mainWindowForwardRequest = UUID()
			} else {
				#if os(visionOS)
				CinemaScene.reopenMainWindow(openWindow, appState: appState)
				#else
				openWindow(id: MeshtasticAppleApp.mainWindowID)
				#endif
			}
		} label: {
			Label {
				Text("Open in App Window", comment: "Button on a panel in the immersive space, shown in place of something that only works in the app window (sharing, saving a file, Apple Maps)")
			} icon: {
				Image(systemName: "arrow.up.forward.app")
			}
		}
	}
}

// MARK: - Sheet content

/// The NavigationStack a sheet's content brings with it. In a panel the content is already
/// pushed onto the panel host's page stack, so it goes without one (a nested stack draws blank
/// there).
struct SheetNavigationStack<Content: View>: View {
	@Environment(\.presentationHost) private var host
	@ViewBuilder let content: () -> Content

	var body: some View {
		switch host {
		case .window: NavigationStack(root: content)
		case .panel: content()
		}
	}
}

/// The `presenting:` forms: SwiftUI's own in a window, the panel versions above in a panel.
private struct HostedPresentingDialog<T, Actions: View, Message: View>: ViewModifier {
	enum Kind {
		case alert, formAlert, confirmation(Visibility)
	}

	let kind: Kind
	let title: Text
	@Binding var isPresented: Bool
	let data: T?
	let actions: (T) -> Actions
	let message: (T) -> Message
	@Environment(\.presentationHost) private var host

	func body(content: Content) -> some View {
		switch (host, kind) {
		case (.window, .alert), (.window, .formAlert):
			content.alert(title, isPresented: $isPresented, presenting: data, actions: actions, message: message)
		case (.window, .confirmation(let visibility)):
			content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: visibility, presenting: data, actions: actions, message: message)
		case (.panel, .alert):
			content.modifier(HostedAlert(title: title, isPresented: panelBinding, actions: panelActions, message: panelMessage))
		case (.panel, .formAlert):
			content.modifier(HostedFormAlert(title: title, isPresented: panelBinding, actions: panelActions, message: panelMessage))
		case (.panel, .confirmation(let visibility)):
			content.modifier(HostedConfirmation(title: title, isPresented: panelBinding, titleVisibility: visibility, actions: panelActions, message: panelMessage))
		}
	}

	/// Shown only while there is data, like SwiftUI's `presenting:` forms.
	private var panelBinding: Binding<Bool> {
		Binding(get: { isPresented && data != nil }, set: { isPresented = $0 })
	}

	private func panelActions() -> PresentedData<T, Actions> {
		PresentedData(data: data, content: actions)
	}

	private func panelMessage() -> PresentedData<T, Message> {
		PresentedData(data: data, content: message)
	}
}

/// The content of a `presenting:` alert or dialog, empty when there is no data.
private struct PresentedData<T, Content: View>: View {
	let data: T?
	let content: (T) -> Content

	var body: some View {
		if let data { content(data) }
	}
}

// MARK: - Panel dialog page and banner

/// What roles the caller's buttons have, so the page knows whether to add its own Cancel.
private struct PanelButtonRoles: Equatable {
	var hasAny = false
	var hasCancel = false
}

private struct PanelButtonRolesKey: PreferenceKey {
	static let defaultValue = PanelButtonRoles()
	static func reduce(value: inout PanelButtonRoles, nextValue: () -> PanelButtonRoles) {
		let next = nextValue()
		value.hasAny = value.hasAny || next.hasAny
		value.hasCancel = value.hasCancel || next.hasCancel
	}
}

/// Draws a dialog's buttons as plain bordered buttons, and closes the dialog after any of them
/// runs its action.
private struct PanelActionButtonStyle: PrimitiveButtonStyle {
	var fullWidth = true
	let close: () -> Void

	func makeBody(configuration: Configuration) -> some View {
		Button(role: configuration.role) {
			configuration.trigger()
			close()
		} label: {
			configuration.label
				.frame(maxWidth: fullWidth ? .infinity : nil)
				// A red tint on a bordered button colors the label red too, on the red fill.
				.foregroundStyle(configuration.role == .destructive ? Color.white : Color.primary)
		}
		.buttonStyle(.bordered)
		.controlSize(.large)
		.tint(configuration.role == .destructive ? .red : nil)
		.preference(key: PanelButtonRolesKey.self, value: PanelButtonRoles(hasAny: true, hasCancel: configuration.role == .cancel))
	}
}

/// The page a confirmation dialog or text field alert becomes in a panel.
private struct PanelDialogPage<Actions: View, Message: View>: View {
	let title: Text?
	let message: Message
	let actions: Actions
	let close: () -> Void
	@State private var roles = PanelButtonRoles()

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				if let title {
					title
						.font(.title3.bold())
						.multilineTextAlignment(.center)
				}
				message
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
				VStack(spacing: 12) {
					actions
				}
				.buttonStyle(PanelActionButtonStyle(close: close))
				.textFieldStyle(.roundedBorder)
				.onPreferenceChange(PanelButtonRolesKey.self) { value in
					Task { @MainActor in roles = value }
				}
				if !roles.hasCancel {
					Button(role: .cancel) {
						close()
					} label: {
						Text("Cancel")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.bordered)
						.controlSize(.large)
				}
			}
			.frame(maxWidth: 480)
			.padding(24)
			.frame(maxWidth: .infinity)
		}
		.navigationBarTitleDisplayMode(.inline)
	}
}

/// The banner an alert becomes in a panel.
private struct PanelBannerCard: View {
	let banner: PanelPresenter.Banner
	@State private var roles = PanelButtonRoles()

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			banner.title
				.font(.headline)
			banner.message
				.font(.subheadline)
				.foregroundStyle(.secondary)
			HStack {
				Spacer()
				banner.actions
					.buttonStyle(PanelActionButtonStyle(fullWidth: false, close: banner.dismiss))
					.onPreferenceChange(PanelButtonRolesKey.self) { value in
						Task { @MainActor in roles = value }
					}
				if !roles.hasAny {
					Button("OK") { banner.dismiss() }
						.buttonStyle(.bordered)
						.controlSize(.large)
				}
			}
		}
		.padding()
		.frame(maxWidth: 560, alignment: .leading)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		.padding()
	}
}
