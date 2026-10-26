//
//  PanelPresenterTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
import SwiftUI
import Testing
@testable import Meshtastic

/// On a panel in the immersive space, sheets and dialogs show as pages on the panel host's own
/// stack. These cover the bookkeeping that keeps each presenting view's flag in step with that
/// stack, so a back tap clears the flag and a cleared flag drops the page.
@Suite("Panel presenter")
@MainActor
struct PanelPresenterTests {

	@Test func windowsAreTheDefaultHost() {
		#expect(EnvironmentValues().presentationHost == .window)
		#expect(EnvironmentValues().panelPresenter == nil)
	}

	@Test func pushAddsAPageOnce() {
		let presenter = PanelPresenter()
		let id = UUID()
		presenter.push(id: id, content: AnyView(Text("A"))) {}
		presenter.push(id: id, content: AnyView(Text("B"))) {}
		#expect(presenter.path == [id])
		#expect(presenter.page(id) != nil)
	}

	@Test func updateOnlyChangesAShowingPage() {
		let presenter = PanelPresenter()
		let id = UUID()
		#expect(!presenter.update(id: id, content: AnyView(Text("A"))))
		#expect(presenter.path.isEmpty)
		presenter.push(id: id, content: AnyView(Text("A"))) {}
		#expect(presenter.update(id: id, content: AnyView(Text("B"))))
		#expect(presenter.path == [id])
	}

	@Test func backTapClearsTheFlagOfThePoppedPage() {
		let presenter = PanelPresenter()
		let first = UUID()
		let second = UUID()
		var firstShown = true
		var secondShown = true
		presenter.push(id: first, content: AnyView(EmptyView())) { firstShown = false }
		presenter.push(id: second, content: AnyView(EmptyView())) { secondShown = false }

		presenter.path = [first]

		#expect(presenter.path == [first])
		#expect(firstShown)
		#expect(!secondShown)
	}

	@Test func poppingAPageAlsoPopsThePagesPushedFromIt() {
		let presenter = PanelPresenter()
		let first = UUID()
		let second = UUID()
		var secondShown = true
		presenter.push(id: first, content: AnyView(EmptyView())) {}
		presenter.push(id: second, content: AnyView(EmptyView())) { secondShown = false }

		presenter.pop(id: first)

		#expect(presenter.path.isEmpty)
		#expect(!secondShown)
	}

	@Test func aNewBannerReplacesTheOldOne() {
		let presenter = PanelPresenter()
		var firstShown = true
		let first = PanelPresenter.Banner(id: UUID(), title: Text("A"), message: AnyView(EmptyView()), actions: AnyView(EmptyView())) { firstShown = false }
		let second = PanelPresenter.Banner(id: UUID(), title: Text("B"), message: AnyView(EmptyView()), actions: AnyView(EmptyView())) {}

		presenter.show(first)
		presenter.show(second)

		#expect(presenter.banner?.id == second.id)
		#expect(!firstShown)

		presenter.removeBanner(id: first.id)
		#expect(presenter.banner?.id == second.id)
		presenter.removeBanner(id: second.id)
		#expect(presenter.banner == nil)
	}

	@Test func popAllClearsEveryPageAndTheBanner() {
		let presenter = PanelPresenter()
		var pageShown = true
		var bannerShown = true
		presenter.push(id: UUID(), content: AnyView(EmptyView())) { pageShown = false }
		presenter.show(PanelPresenter.Banner(id: UUID(), title: Text("A"), message: AnyView(EmptyView()), actions: AnyView(EmptyView())) { bannerShown = false })

		presenter.popAll()

		#expect(presenter.path.isEmpty)
		#expect(presenter.banner == nil)
		#expect(!pageShown)
		#expect(!bannerShown)
	}
}
