//
//  DeviceScreenView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import GameController
import MeshtasticProtobufs
import SwiftUI

/// The connected radio's own screen, live, with its buttons. Streams only while this view is on
/// screen and the app is active, and stops when it closes (design#142).
struct DeviceScreenView: View {

	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.scenePhase) private var scenePhase
	let metadata: DeviceMetadataEntity

	@FocusState private var keyboardCaptured: Bool
	@State private var hasKeyboard = DeviceScreenView.keyboardAttached
	@State private var press: ScreenPress?
	@State private var lastKeyRepeat = Date.distantPast

	private static var keyboardAttached: Bool {
		ProcessInfo.processInfo.isMacCatalystApp || GCKeyboard.coalesced != nil
	}

	private var aspectRatio: CGFloat {
		CGFloat(max(metadata.displayWidth, 1)) / CGFloat(max(metadata.displayHeight, 1))
	}

	private var isEInk: Bool {
		DisplayInfo.PanelClass(rawValue: Int(metadata.displayPanelClass)) == .eink
	}

	var body: some View {
		Group {
			if accessoryManager.isConnected {
				ScrollView {
					VStack(spacing: 16) {
						screen
						DeviceRemoteControl { event in
							Task { await accessoryManager.sendDisplayInput(event) }
						}
						details
					}
					.padding(16)
					.frame(maxWidth: 640)
					.frame(maxWidth: .infinity)
				}
			} else {
				ContentUnavailableView(
					"Not Connected",
					systemImage: "display",
					description: Text("Connect to the radio to see its screen.")
				)
			}
		}
		.navigationTitle("Device Screen")
		.navigationBarTitleDisplayMode(.inline)
		.task { await startIfVisible() }
		.onDisappear {
			Task { await accessoryManager.stopDisplayMirror() }
		}
		.onChange(of: scenePhase) { _, phase in
			Task {
				if phase == .active {
					await startIfVisible()
				} else {
					await accessoryManager.stopDisplayMirror()
				}
			}
		}
		.onChange(of: accessoryManager.isConnected) { _, connected in
			// The radio forgets the stream on reconnect, so ask again.
			if connected {
				Task { await startIfVisible() }
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in
			hasKeyboard = Self.keyboardAttached
		}
		.onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in
			hasKeyboard = Self.keyboardAttached
			if !hasKeyboard {
				keyboardCaptured = false
			}
		}
		.trackScreen(.deviceScreen)
	}

	private var screen: some View {
		ZStack {
			if let image = accessoryManager.displayMirror.image {
				Image(decorative: image, scale: 1)
					.resizable()
					.interpolation(.none)
					// The picture's own shape, so touches line up with the pixels drawn.
					.aspectRatio(contentMode: .fit)
					.overlay {
						GeometryReader { proxy in
							Color.clear
								.contentShape(Rectangle())
								.gesture(screenGesture(renderedSize: proxy.size, panelWidth: image.width, panelHeight: image.height))
						}
					}
					.accessibilityElement()
					.accessibilityLabel("Radio screen")
			} else {
				Color.black
					.aspectRatio(aspectRatio, contentMode: .fit)
					.overlay {
						VStack(spacing: 8) {
							ProgressView()
								.tint(.white)
							Text("Waiting for the radio's screen")
								.font(.footnote)
								.foregroundStyle(.white)
						}
					}
			}
		}
		.padding(10)
		.background(.black, in: RoundedRectangle(cornerRadius: 12))
		.overlay {
			if keyboardCaptured {
				RoundedRectangle(cornerRadius: 12)
					.strokeBorder(Color.accentColor, lineWidth: 3)
			}
		}
		.focusable(hasKeyboard)
		.focused($keyboardCaptured)
		.focusEffectDisabled()
		.onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .escape, .delete], phases: .all) { press in
			handleKey(press)
		}
	}

	/// A swipe sends a direction. On touch screens a tap touches the pixel under it and a long
	/// press long-presses it; the radio times the long press itself, so it's sent once.
	private func screenGesture(renderedSize: CGSize, panelWidth: Int, panelHeight: Int) -> some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { value in
				// Keyed by where the touch began, so a canceled touch that never ended can't
				// lend its start time to the next one.
				if press?.start != value.startLocation {
					press = ScreenPress(start: value.startLocation, time: value.time)
				}
			}
			.onEnded { value in
				let heldFor = press.flatMap { $0.start == value.startLocation ? value.time.timeIntervalSince($0.time) : nil } ?? 0
				press = nil
				if let direction = DisplayInputMapping.swipeDirection(for: value.translation) {
					send(direction)
					return
				}
				guard metadata.displayHasTouch,
					  let point = DisplayInputMapping.panelPoint(
						for: value.location,
						in: renderedSize,
						panelWidth: panelWidth,
						panelHeight: panelHeight
					  ) else { return }
				send(heldFor >= DisplayInputMapping.longPressDuration ? .select : .userPress, at: point)
			}
	}

	/// Arrow keys, Return/Space and Esc/Delete go to the radio while the screen has keyboard focus.
	/// Key-ups are swallowed too, and anything held with Command, Control or Option is left alone.
	private func handleKey(_ press: KeyPress) -> KeyPress.Result {
		guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
		let event: DisplayInputEvent
		switch press.key {
		case .upArrow: event = .up
		case .downArrow: event = .down
		case .leftArrow: event = .left
		case .rightArrow: event = .right
		case .return, .space: event = .select
		case .escape, .delete: event = .back
		default: return .ignored
		}
		switch press.phase {
		case .down:
			send(event)
		case .repeat:
			// Only directions repeat, and no faster than the on-screen ring does.
			let now = Date.now
			if event.isDirection, now.timeIntervalSince(lastKeyRepeat) >= 0.1 {
				lastKeyRepeat = now
				send(event)
			}
		default:
			break
		}
		return .handled
	}

	private func send(_ event: DisplayInputEvent, at point: DisplayTouchPoint? = nil) {
		Task { await accessoryManager.sendDisplayInput(event, at: point) }
	}

	private var details: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(panelDescription)
				.font(.footnote)
				.foregroundStyle(.secondary)
			if isEInk {
				Text("E-ink screens redraw slowly. Tap Refresh for the latest picture.")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			if keyboardCaptured {
				Text("Arrow keys, Return and Esc go to the radio.")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			HStack {
				Button {
					Task { await accessoryManager.requestDisplayFrame() }
				} label: {
					Label("Refresh", systemImage: "arrow.clockwise")
				}
				if hasKeyboard {
					Button {
						keyboardCaptured.toggle()
					} label: {
						if keyboardCaptured {
							Label("Stop Using Keyboard", systemImage: "keyboard.chevron.compact.down")
						} else {
							Label("Use Keyboard", systemImage: "keyboard")
						}
					}
				}
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.roundedRectangle)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var panelDescription: String {
		let size = "\(metadata.displayWidth) × \(metadata.displayHeight)"
		switch DisplayInfo.PanelClass(rawValue: Int(metadata.displayPanelClass)) {
		case .oled: return String(localized: "\(size) OLED")
		case .lcd: return String(localized: "\(size) LCD")
		case .tft: return String(localized: "\(size) TFT")
		case .eink: return String(localized: "\(size) E-ink")
		case .hub75: return String(localized: "\(size) LED matrix")
		default: return size
		}
	}

	private func startIfVisible() async {
		guard accessoryManager.isConnected, scenePhase == .active else { return }
		await accessoryManager.startDisplayMirror()
	}
}

private struct ScreenPress {
	let start: CGPoint
	let time: Date
}
