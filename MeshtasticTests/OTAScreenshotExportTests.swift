//
//  OTAScreenshotExportTests.swift
//  MeshtasticTests
//

import XCTest
import SwiftUI
import UIKit
@testable import Meshtastic

private struct RealisticSheetModalView<Content: View>: View {
	let content: Content

	init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	var body: some View {
		ZStack(alignment: .bottom) {
			// Dimmed app screen behind the modal sheet
			Color(red: 0.06, green: 0.06, blue: 0.07)
				.ignoresSafeArea()

			VStack(spacing: 0) {
				// iOS sheet grabber handle
				Capsule()
					.fill(Color(white: 0.45))
					.frame(width: 36, height: 5)
					.padding(.top, 10)
					.padding(.bottom, 6)

				content
			}
			.background(Color(red: 0.11, green: 0.11, blue: 0.12))
			.clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
			.frame(maxHeight: 745)
		}
		.preferredColorScheme(.dark)
		.environment(\.colorScheme, .dark)
	}
}

final class OTAScreenshotExportTests: XCTestCase {
	@MainActor
	func testExportOTAScreenshots() throws {
		let downloadsURL = URL(fileURLWithPath: "/Users/benjaminfaershtein/Downloads")
		let width: CGFloat = 393
		let height: CGFloat = 852

		func saveScreenshot(_ view: some View, filename: String) {
			let modalView = RealisticSheetModalView {
				view
			}
			let hostingController = UIHostingController(rootView: AnyView(modalView.frame(width: width, height: height)))
			hostingController.overrideUserInterfaceStyle = .dark
			hostingController.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
			hostingController.view.backgroundColor = .black

			let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
			window.overrideUserInterfaceStyle = .dark
			window.rootViewController = hostingController
			window.makeKeyAndVisible()
			hostingController.view.setNeedsLayout()
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
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {} label: {
						Image(systemName: "xmark")
					}
				}
			}
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

		// 3. Nordic DFU Sheet
		let nrfDFUView = NRFDFUSheet(showWarningAlert: false, firmwareToFlash: URL(fileURLWithPath: "/tmp/firmware-nrf52840.zip"))
			.environmentObject(AccessoryManager.shared)
		saveScreenshot(nrfDFUView, filename: "ota_06_nordic_nrf_dfu.png")
	}
}
