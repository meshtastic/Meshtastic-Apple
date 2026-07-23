import SpriteKit
import SwiftUI

struct FirmwareUpdateGameButton: View {
	@Binding var isPresented: Bool
	let status: FirmwareUpdateGameStatus

	var body: some View {
		Button {
			isPresented = true
		} label: {
			Label("Play Chirpy Hop", systemImage: "gamecontroller.fill")
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.borderedProminent)
		.controlSize(.large)
		.disabled(!status.canPlay)
		.accessibilityIdentifier("chirpy-ota-game-button")
	}
}

struct FirmwareUpdateGameScreen: View {
	let status: FirmwareUpdateGameStatus
	let onClose: () -> Void
	@State private var scene = ChirpyRunnerScene(size: CGSize(width: 900, height: 620))
	@State private var crouchGestureActive = false

	var body: some View {
		VStack(spacing: 0) {
			FirmwareUpdateStatusBand(status: status, onClose: onClose)

			ZStack {
				SpriteView(scene: scene)
					.allowsHitTesting(false)

				Color.black.opacity(0.001)
					.contentShape(Rectangle())
					.gesture(gameGesture)
					.accessibilityLabel(String(localized: "Chirpy Hop", comment: "VoiceOver label for the Chirpy game play surface"))
					.accessibilityHint(String(localized: "Tap to jump or swipe down to crouch", comment: "VoiceOver hint for the Chirpy game controls"))
					.accessibilityAddTraits(.isButton)
					.accessibilityAction {
						scene.primaryAction()
					}
					.accessibilityIdentifier("chirpy-game-surface")

				if !status.phase.isActive {
					FirmwareUpdateFinishedOverlay(status: status, onClose: onClose)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			HStack(spacing: 8) {
				Image(systemName: "hand.tap.fill")
				Image(systemName: "arrow.up")
				Divider()
					.frame(height: 22)
					.padding(.horizontal, 10)
				Image(systemName: "hand.draw.fill")
				Image(systemName: "arrow.down")
			}
			.font(.headline)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity)
			.frame(height: 48)
			.background(Color(uiColor: .secondarySystemBackground))
		}
		.background(Color(uiColor: .systemBackground))
		.ignoresSafeArea(edges: .bottom)
		.onAppear {
			scene.setUpdateActive(status.phase.isActive)
		}
		.onChange(of: status.phase) { _, phase in
			scene.setUpdateActive(phase.isActive)
		}
		.onDisappear {
			scene.setCrouching(false)
		}
	}

	private var gameGesture: some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { value in
				guard status.phase.isActive else {
					return
				}
				let shouldCrouch = value.translation.height > 18
				if shouldCrouch != crouchGestureActive {
					crouchGestureActive = shouldCrouch
					scene.setCrouching(shouldCrouch)
				}
			}
			.onEnded { _ in
				guard status.phase.isActive else {
					return
				}
				if crouchGestureActive {
					crouchGestureActive = false
					scene.setCrouching(false)
				} else {
					scene.primaryAction()
				}
			}
	}
}

private struct FirmwareUpdateStatusBand: View {
	let status: FirmwareUpdateGameStatus
	let onClose: () -> Void

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Button(action: onClose) {
				Image(systemName: "chevron.backward")
					.font(.headline)
					.frame(width: 38, height: 38)
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.circle)
			.accessibilityLabel(String(localized: "Back to firmware update", comment: "VoiceOver label for the close button in the Chirpy game"))
			.accessibilityIdentifier("chirpy-game-close")

			VStack(alignment: .leading, spacing: 7) {
				HStack(alignment: .firstTextBaseline) {
					Label(status.title, systemImage: "arrow.triangle.2.circlepath")
						.font(.headline)
						.lineLimit(1)
					Spacer(minLength: 8)
					Text(status.percentText)
						.font(.headline.monospacedDigit())
				}

				ProgressView(value: status.progress, total: 1)
					.tint(status.phase == .failed ? .red : .accentColor)

				Text(status.message)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.background(.regularMaterial)
		.overlay(alignment: .bottom) {
			Divider()
		}
	}
}

private struct FirmwareUpdateFinishedOverlay: View {
	let status: FirmwareUpdateGameStatus
	let onClose: () -> Void

	var body: some View {
		VStack(spacing: 14) {
			Image(systemName: status.phase == .complete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
				.font(.system(size: 44))
				.foregroundStyle(status.phase == .complete ? .green : .red)

			Text(status.phase == .complete ? "Update Complete" : "Update Interrupted")
				.font(.title2.bold())

			Text(status.message)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			Button("Back to Update", action: onClose)
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
		}
		.padding(24)
		.frame(maxWidth: 320)
		.background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
		.shadow(color: .black.opacity(0.18), radius: 18, y: 8)
		.padding()
	}
}

private struct FirmwareUpdateGamePresentationModifier: ViewModifier {
	@Binding var isPresented: Bool
	let status: FirmwareUpdateGameStatus

	func body(content: Content) -> some View {
		content.overlay {
			if isPresented {
				FirmwareUpdateGameScreen(status: status) {
					isPresented = false
				}
				.transition(.move(edge: .bottom).combined(with: .opacity))
				.zIndex(100)
			}
		}
		.animation(.easeInOut(duration: 0.22), value: isPresented)
	}
}

extension View {
	func firmwareUpdateGame(isPresented: Binding<Bool>, status: FirmwareUpdateGameStatus) -> some View {
		modifier(FirmwareUpdateGamePresentationModifier(isPresented: isPresented, status: status))
	}
}

struct FirmwareUpdateGameDemoHost: View {
	#if DEBUG
	@State private var upload = FirmwareUpdateDemoState(duration: 300)
	@State private var showGame = false

	var body: some View {
		NavigationStack {
			VStack(spacing: 18) {
				VStack(spacing: 4) {
					Text("Mock OTA Upload")
						.font(.title2.bold())
					Text("No radio or firmware file is used")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				CircularProgressView(
					progress: upload.status.progress,
					isIndeterminate: upload.status.phase == .preparing,
					size: 220,
					subtitleText: upload.status.message
				)
				.frame(minHeight: 245)

				Text(upload.status.message)
					.font(.headline)
					.multilineTextAlignment(.center)
					.padding(.horizontal)

				Spacer()

				VStack(spacing: 10) {
					FirmwareUpdateGameButton(isPresented: $showGame, status: upload.status)

					Button {
						upload.reset()
					} label: {
						Label("Restart Mock Upload", systemImage: "arrow.clockwise")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.bordered)
					.controlSize(.large)
					.accessibilityIdentifier("chirpy-demo-restart")
				}
				.padding(.horizontal)
				.padding(.bottom)
			}
			.padding(.top)
			.navigationTitle("Firmware Update")
			.navigationBarTitleDisplayMode(.inline)
		}
		.firmwareUpdateGame(isPresented: $showGame, status: upload.status)
		.task {
			while !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(100))
				upload.advance(by: 0.1)
			}
		}
	}
	#else
	var body: some View {
		EmptyView()
	}
	#endif
}

#if DEBUG
#Preview("Mock OTA") {
	FirmwareUpdateGameDemoHost()
}
#endif
