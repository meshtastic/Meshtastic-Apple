//
//  OTAScreenshotExportTests.swift
//  MeshtasticTests
//

import XCTest
import SwiftUI
import UIKit
@testable import Meshtastic

final class OTAScreenshotExportTests: XCTestCase {
	@MainActor
	func testExportOTAScreenshots() throws {
		let downloadsURL = URL(fileURLWithPath: "/Users/benjaminfaershtein/Downloads")
		let width: CGFloat = 393
		let height: CGFloat = 852

		func saveScreenshot(_ view: some View, filename: String) {
			let hostingController = UIHostingController(rootView: AnyView(view.frame(width: width, height: height)))
			hostingController.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
			hostingController.view.backgroundColor = .systemBackground

			let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
			window.rootViewController = hostingController
			window.isHidden = false
			hostingController.view.layoutIfNeeded()

			let format = UIGraphicsImageRendererFormat()
			format.scale = 3.0
			let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
			let image = renderer.image { _ in
				hostingController.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: width, height: height), afterScreenUpdates: true)
			}

			if let pngData = image.pngData() {
				let fileURL = downloadsURL.appendingPathComponent(filename)
				try? pngData.write(to: fileURL)
			}
		}

		// 1. Before Fix (Old UI: Cluttered with top metadata section, squished circular ring, and crowded layout)
		let beforeView = NavigationStack {
			List {
				Section {
					VStack(alignment: .leading, spacing: 2) {
						Text("Firmware File")
							.foregroundStyle(.secondary)
							.font(.caption)
						Text("firmware-esp32s3-tbeam-2.5.18.bin")
							.font(.caption)
					}
					VStack(alignment: .leading, spacing: 2) {
						Text("BLE Device")
							.foregroundStyle(.secondary)
							.font(.caption)
						Text("Meshtastic-B012\n9F82A02C-6194-4B02-B792-F1242398C29E")
							.font(.caption)
					}
				} header: {
					Text("Please do not leave this screen until this process is complete.")
				} footer: {
					Text("Please be sure this is correct before proceeding.")
				}

				Section {
					HStack {
						Spacer()
						CircularProgressView(
							progress: 0.45,
							isIndeterminate: false,
							isError: false,
							size: 225.0,
							subtitleText: "transferring"
						)
						.frame(minHeight: 250.0)
						Spacer()
					}
					.listRowBackground(Color.clear)

					VStack(spacing: 12) {
						Text("Uploading firmware (45%)...")
							.frame(maxWidth: .infinity)
							.font(.headline)
					}
					.listRowBackground(Color.clear)
				}
				.listRowSeparator(.hidden)

				Section {
					Button {} label: {
						Label("Play Chirpy Hop", systemImage: "gamecontroller.fill")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)
				}
			}
			.navigationTitle("ESP32 BLE Updater")
			.navigationBarTitleDisplayMode(.inline)
		}
		saveScreenshot(beforeView, filename: "ota_ui_before_fix.png")

		// 2. After Fix (New UI: Unified, clean centered layout, no truncation, Chirpy Hop safe notice)
		let afterView = FirmwareOTAUpdateSheet(
			title: "ESP32 BLE Updater",
			progress: 0.45,
			statusState: .transferring,
			statusMessage: "Uploading firmware (45%)...",
			inRetryWorkflow: false,
			isStartDisabled: false,
			onStart: {},
			onRetry: {},
			onDismiss: {},
			gameTitle: "ESP32 BLE OTA"
		)
		saveScreenshot(afterView, filename: "ota_ui_after_fix.png")

		// 3. Mini-Game Gameplay (Full Screen Chirpy Hop)
		let gameStatus = FirmwareUpdateGameStatus(
			title: "ESP32 BLE OTA",
			message: "Uploading firmware (45%)...",
			progress: 0.45,
			phase: .uploading
		)
		let gameView = FirmwareUpdateGameScreen(status: gameStatus, onClose: {})
		saveScreenshot(gameView, filename: "ota_chirpy_hop_gameplay.png")
	}
}
