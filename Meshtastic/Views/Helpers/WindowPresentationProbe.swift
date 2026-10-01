//
//  WindowPresentationProbe.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI
import UIKit

/// Tells whether a view's window is presenting anything: a sheet, cover or alert, a sheet the app
/// opened further in included (feature 021, review V13 R13-1, V14 P3).
///
/// A window shows one presentation at a time, and one asked for while another is up can be lost.
/// With several radios the one window's own sheets, gates and prompts are asked for only when
/// this says the window is free.
@MainActor
final class WindowPresentationProbe {
	fileprivate weak var view: UIView?

	/// Whether any view controller in the window presents something. False while the view isn't
	/// in a window.
	var isPresenting: Bool {
		guard let root = view?.window?.rootViewController else { return false }
		return Self.presents(root)
	}

	private static func presents(_ controller: UIViewController) -> Bool {
		controller.presentedViewController != nil || controller.children.contains { presents($0) }
	}
}

/// Puts `probe` in the view hierarchy, so it can find its window. Draws nothing.
struct WindowPresentationProbeView: UIViewRepresentable {
	let probe: WindowPresentationProbe

	func makeUIView(context: Context) -> UIView {
		let view = UIView()
		view.isUserInteractionEnabled = false
		probe.view = view
		return view
	}

	func updateUIView(_ uiView: UIView, context: Context) {
		probe.view = uiView
	}
}
