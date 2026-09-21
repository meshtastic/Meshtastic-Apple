//
//  AmbientLightingColorTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/21/26.
//
import Testing
import SwiftUI
import SwiftData
import UIKit
@testable import Meshtastic
import MeshtasticProtobufs

/// The ambient lighting screen edits red, green and blue through one color picker. The
/// picker's row appears before the form has loaded the config, so a picker that keeps
/// its own copy of the color starts at a default and then writes that default back over
/// the channels that arrive.
@Suite("Ambient lighting color")
struct AmbientLightingColorTests {

	@MainActor
	private func makeNode(red: Int32, green: Int32, blue: Int32) throws -> NodeInfoEntity {
		let context = sharedModelContainer.mainContext
		let node = NodeInfoEntity()
		node.num = 0xA1B2_C301
		context.insert(node)
		let user = UserEntity()
		user.num = node.num
		user.longName = "Ambient Color Node"
		user.shortName = "ALED"
		context.insert(user)
		node.user = user
		let lighting = AmbientLightingConfigEntity()
		lighting.ledState = true
		lighting.current = 12
		lighting.red = red
		lighting.green = green
		lighting.blue = blue
		context.insert(lighting)
		node.ambientLightingConfig = lighting
		try context.save()
		return node
	}

	/// Hosts the view in a window so appearance and the state changes it causes really run.
	/// A window has to be given a size before anything lays out, and a test wants the same
	/// one every run. Phone-shaped so the rows lay out the way they do in the app.
	private static let hostSize = CGSize(width: 390, height: 700)

	@MainActor
	private func host<V: View>(_ view: V) {
		let size = Self.hostSize
		let hosting = UIHostingController(rootView: view.frame(width: size.width))
		let window = UIWindow(frame: CGRect(origin: .zero, size: size))
		window.rootViewController = hosting
		window.isHidden = false
		hosting.view.frame = CGRect(origin: .zero, size: size)
		window.layoutIfNeeded()
		hosting.view.setNeedsLayout()
		hosting.view.layoutIfNeeded()
		hosting.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
	}

	@Test("The color picker keeps the channels the form loaded")
	@MainActor
	func loadedColorSurvives() async throws {
		let node = try makeNode(red: 40, green: 200, blue: 90)
		AccessoryManager.shared.isConnected = true
		AccessoryManager.shared.activeDeviceNum = node.num
		let recorder = ChannelRecorder()

		host(
			NavigationStack {
				MetadataConfigForm(
					node: node,
					title: "Ambient Lighting",
					overlay: AmbientLightingConfig.overlay(),
					request: { _, _ in },
					save: { _, _, _ in },
					trailing: { config in RecorderRow(config: config, recorder: recorder) }
				)
			}
			.environmentObject(AccessoryManager.shared)
			.modelContainer(sharedModelContainer)
		)

		#expect(recorder.channels == [40, 200, 90])
	}

	@Test("Every channel value survives a trip through Color and back")
	@MainActor
	func channelsRoundTrip() async throws {
		let environment = EnvironmentValues()
		var wrong: [Int] = []
		for value in 0...255 {
			let shown = AmbientChannels.color(red: UInt32(value), green: UInt32(value), blue: UInt32(value))
			let resolved = shown.resolve(in: environment)
			if AmbientChannels.level(resolved.red) != UInt32(value) { wrong.append(value) }
		}
		#expect(wrong.isEmpty, "channels that did not come back: \(wrong)")
	}

	@Test @MainActor
	func aWideGamutColorIsClampedRatherThanTrapping() {
		// Color.resolve does not clamp to sRGB, so a P3 colour comes back outside 0...1 —
		// pure P3 green resolves with red near -0.5. Rounding that straight into UInt32
		// traps, so the clamp is load-bearing, not defensive.
		#expect(AmbientChannels.level(-0.51) == 0)
		#expect(AmbientChannels.level(1.4) == 255)
		// And the ordinary range still rounds rather than truncating.
		#expect(AmbientChannels.level(0) == 0)
		#expect(AmbientChannels.level(1) == 255)
		#expect(AmbientChannels.level(0.5) == 128)
		#expect(AmbientChannels.level(100.4 / 255) == 100)
		#expect(AmbientChannels.level(100.6 / 255) == 101)
	}
}

/// Holds what the form's message last held, for the test to read after the render.
@MainActor
private final class ChannelRecorder {
	var channels: [UInt32] = []
}

/// A row that reports the message every time it changes.
private struct RecorderRow: View {
	@Binding var config: ModuleConfig.AmbientLightingConfig
	let recorder: ChannelRecorder

	var body: some View {
		Color.clear
			.frame(height: 0)
			.onAppear { record() }
			.onChange(of: config) { _, _ in record() }
	}

	private func record() {
		recorder.channels = [config.red, config.green, config.blue]
	}
}
