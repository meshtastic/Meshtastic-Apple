//
//  Firmware.swift
//  Meshtastic
//
//   Copyright(c) by Garth Vander Houwen on 3/10/23.
//

import SwiftUI
import SwiftData
import StoreKit
import OSLog
import SwiftDraw
import UniformTypeIdentifiers
import WebKit

// 1. THE WRAPPER
// Caches the resolved hardware so SwiftData re-evaluations don't flash the
// "reconnect" screen when relationships momentarily fault to nil.
struct Firmware: View {
	let node: NodeInfoEntity?

	@Query var hardwareResults: [DeviceHardwareEntity]
	@State private var cachedHardware: DeviceHardwareEntity?
	@State private var cachedNode: NodeInfoEntity?

	init(node: NodeInfoEntity?) {
		self.node = node

		if let pioEnv = node?.myInfo?.pioEnv {
			_hardwareResults = Query(filter: #Predicate<DeviceHardwareEntity> { hw in
				hw.platformioTarget == pioEnv
			})
		} else {
			_hardwareResults = Query(filter: #Predicate<DeviceHardwareEntity> { _ in false })
		}
	}

	var body: some View {
		Group {
			if let resolvedNode = cachedNode, let resolvedHardware = cachedHardware {
				FirmwareContentView(node: resolvedNode, hardware: resolvedHardware)
					.id(resolvedNode.num)
			} else {
				List {
					ContentUnavailableView("Firmware Updates",
						systemImage: "arrow.triangle.2.circlepath",
						description: Text("Please reconnect to your device to load firmware information."))
				}
			}
		}
		.onAppear {
			resolveHardware()
		}
		.onChange(of: hardwareResults) {
			resolveHardware()
		}
	}

	private func resolveHardware() {
		// Only update cache when we have valid data — never clear it
		if let node, node.myInfo?.pioEnv != nil, let hardware = hardwareResults.first {
			cachedNode = node
			cachedHardware = hardware
		}
	}
}

// 2. THE CONTENT
// Decoupled from fetching logic.
private struct FirmwareContentView: View {
	
	private enum FirmwareTab {
		case stable, alpha, downloaded
	}
	
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	
	let node: NodeInfoEntity
	let hardware: DeviceHardwareEntity
	
	// We can safely init the StateObject here because 'hardware' is passed in
	@StateObject var firmwareList: FirmwareViewModel
	@State private var firmwareSelection = FirmwareTab.stable
	
	// For Catalyst file picker
	@State var showFirmwareFilePicker = false
	@State var showInstallationSheet: FirmwareFile.FirmwareType?
	@State var locallyChosenFirmwareFile: URL?
	// For row-level install sheet
	@State var rowInstallation: RowInstallation?

	struct RowInstallation: Identifiable {
		let type: FirmwareFile.FirmwareType
		let url: URL
		var id: String { "\(type.rawValue)-\(url.absoluteString)" }
	}
	
	init(node: NodeInfoEntity, hardware: DeviceHardwareEntity) {
		self.node = node
		self.hardware = hardware
		_firmwareList = StateObject(wrappedValue: FirmwareViewModel(forHardware: hardware))
	}
	
	var body: some View {
		List {
			// SECTION 1: HERO
			Section {
				Text(hardware.displayName ?? "Unknown")
					.font(.title)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.bottom, 2)

				HStack(alignment: .center, spacing: 12) {
					SupportedHardwareBadge(hwModelId: hardware.hwModel)
						.frame(width: 72)
						.padding(.leading, 4)

					FirmwareHeroImage(hardware: hardware)
						.frame(maxWidth: .infinity)
						.frame(height: 140)
				}
				.padding(.bottom, 2)

				VStack(alignment: .leading) {
					Text("Platform IO").font(.caption).foregroundColor(.secondary)
					Text("\(node.myInfo?.pioEnv ?? "Unknown")")
				}
				VStack(alignment: .leading) {
					Text("Architecture").font(.caption).foregroundColor(.secondary)
					Text("\(hardware.architecture ?? "Unknown")")
				}
				VStack(alignment: .leading) {
					Text("Current Firmware Version").font(.caption).foregroundColor(.secondary)
					Text("\(node.metadata?.firmwareVersion ?? "Unknown")")
				}
			}
			.listRowSeparator(.hidden)

			// SECTION 2: RELEASES
			Section(header: releasesHeader, footer: lastUpdatedFooter) {
				Picker("Firmware Version", selection: $firmwareSelection) {
					Text("Stable").tag(FirmwareTab.stable)
					Text("Alpha").tag(FirmwareTab.alpha)
					Text("Downloaded").tag(FirmwareTab.downloaded)
				}.pickerStyle(.segmented)
				
				// Extracted switch logic to keep body clean
				firmwareRows
			}
		}
		.navigationTitle("Firmware Updates")
		.navigationBarTitleDisplayMode(.inline)
		.onChange(of: meshtasticAPI.isLoadingFirmwareList) { _, isLoading in
			if !isLoading {
				firmwareList.refresh()
			}
		}
		.sheet(item: $rowInstallation) { installation in
			switch installation.type {
			case .otaZip:
				NRFDFUSheet(firmwareToFlash: installation.url)
			case .uf2:
				UF2MassStorageView(fileURL: installation.url)
			case .bin:
				ESP32OTAIntroSheet(binFileURL: installation.url)
			}
		}
	}
	
	// MARK: - Subviews
	
	@ViewBuilder
	var firmwareRows: some View {
		switch firmwareSelection {
		case .stable:
			let stables = firmwareList.mostRecentFirmware(forReleaseType: .stable)
			ForEach(stables, id: \.localUrl) { release in
				FirmwareRow(firmwareFile: release) { type, url in
					self.rowInstallation = RowInstallation(type: type, url: url)
				}
			}
			if let last = stables.last, let notes = last.releaseNotes {
				NavigationLink("Release Notes") {
					FirmwareReleaseNotesView(markdown: notes, versionId: last.versionId)
				}
			}
		case .alpha:
			let alphas = firmwareList.mostRecentFirmware(forReleaseType: .alpha)
			ForEach(alphas, id: \.localUrl) { release in
				FirmwareRow(firmwareFile: release) { type, url in
					self.rowInstallation = RowInstallation(type: type, url: url)
				}
			}
			if let last = alphas.last, let notes = last.releaseNotes {
				NavigationLink("Release Notes") {
					FirmwareReleaseNotesView(markdown: notes, versionId: last.versionId)
				}
			}
		case .downloaded:
			let downloads = firmwareList.downloadedFirmware(includeInProgressDownloads: true)
			if downloads.isEmpty {
				Text("No firmware has been downloaded for this device.")
			} else {
				ForEach(downloads, id: \.localUrl) { file in
					FirmwareRow(firmwareFile: file) { type, url in
						self.rowInstallation = RowInstallation(type: type, url: url)
					}
				}
				.onDelete { offsets in
					let files = offsets.map { downloads[$0] }
					firmwareList.delete(files)
				}
			}
		}
	}
	
	var lastUpdatedFooter: some View {
		HStack(alignment: .firstTextBaseline, spacing: 0) {
			if meshtasticAPI.isLoadingFirmwareList {
				Text("Updating now...")
			} else {
				if UserDefaults.lastFirmwareAPIUpdate == .distantPast {
					Text("Last Updated: Never")
				} else {
					Text("Last Updated: \(UserDefaults.lastFirmwareAPIUpdate.formatted(date: .numeric, time: .shortened))")
				}
			}
		}
	}
	
	var allowedTypes: [UTType] {
		switch hardware.architecture.flatMap( {Architecture(rawValue: $0) }) {
		case .esp32, .esp32C3, .esp32S3, .esp32C6:
			return [.BINFirmware]
		case .nrf52840:
			return [.ZIPFirmware, .UF2Firmware]
		case .rp2040:
			return [.UF2Firmware]
		default:
			return []
		}
	}

	var releasesHeader: some View {
		#if targetEnvironment(macCatalyst)
		HStack {
			Text("Firmware Releases")
			Spacer()
			Button("Open Local File...") {
				self.showFirmwareFilePicker = true
			}.buttonStyle(.bordered)
			.controlSize(.small)
			.fileImporter(
				isPresented: $showFirmwareFilePicker,
				allowedContentTypes: self.allowedTypes,
				allowsMultipleSelection: false
			) { result in
				do {
					guard let selectedFile: URL = try result.get().first else { return }
					self.locallyChosenFirmwareFile = selectedFile

					switch hardware.architecture.flatMap( {Architecture(rawValue: $0) }) {
					case .esp32, .esp32C3, .esp32S3, .esp32C6:
						if selectedFile.pathExtension.lowercased() == "bin" {
							self.showInstallationSheet = .bin
						}
					case .nrf52840:
						switch selectedFile.pathExtension.lowercased() {
						case "uf2":
							self.showInstallationSheet = .uf2
						case "zip":
							self.showInstallationSheet = .otaZip
						default:
							break
						}
					case .rp2040:
						if selectedFile.pathExtension.lowercased() == "uf2" {
							self.showInstallationSheet = .uf2
						}
					default:
						break
					}
				} catch {
					Logger.services.error("Failed to load firmware file: \(error.localizedDescription)")
				}
			}.sheet(item: $showInstallationSheet) { type in
				if let locallyChosenFirmwareFile = self.locallyChosenFirmwareFile {
					switch type {
					case .otaZip:
						NRFDFUSheet(firmwareToFlash: locallyChosenFirmwareFile)
					case .uf2:
						UF2MassStorageView(fileURL: locallyChosenFirmwareFile)
					case .bin:
						ESP32OTAIntroSheet(binFileURL: locallyChosenFirmwareFile)
					}
				}
			}
			if meshtasticAPI.isLoadingFirmwareList {
				ProgressView()
			} else {
				Button {
					Task.detached {
						try? await meshtasticAPI.refreshFirmwareAPIData()
					}
				} label: {
					Image(systemName: "arrow.clockwise.circle")
				}
				.buttonStyle(.bordered)
			}
		}.textCase(nil)
		#else
		HStack {
			Text("Firmware Releases")
			Spacer()
			if meshtasticAPI.isLoadingFirmwareList {
				ProgressView()
			} else {
				Button {
					Task.detached {
						try? await meshtasticAPI.refreshFirmwareAPIData()
					}
				} label: {
					Image(systemName: "arrow.clockwise.circle")
				}
			}
		}.textCase(nil)
		#endif
	}
}

// 3. THE ISOLATED HERO IMAGE
// This stops an infinite rendering loop. It loads the SVG data once into State,
// preventing the List layout pass from triggering Core Data faults repeatedly.
struct FirmwareHeroImage: View {
	let hardware: DeviceHardwareEntity
	@State private var svg: SVG?
	
	var body: some View {
		Group {
			if let svg = svg {
				SVGView(svg: svg)
					.resizable()
					.scaledToFit()
					.cornerRadius(5)
			} else {
				// Placeholder prevents List jumpiness while loading
				Color.clear
					.frame(height: 140)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: 140)
		.task {
			// Perform the Core Data relationship traversal off the main layout pass
			if svg == nil {
				self.svg = getSVG()
			}
		}
	}
	
	private func getSVG() -> SVG? {
		let images = hardware.images
		if let image = images.first,
		   let data = image.svgData,
		   let svg = SVG(data: data) {
			return svg
		}
		return nil
	}
}

struct FirmwareTagView: View {
	let text: String
	let color: Color
	init(_ text: String, color: Color = .black) {
		self.text = text
		self.color = color
	}
	var body: some View {
		Text(text)
			.foregroundStyle(color)
			.padding(.horizontal, 2.0)
			.padding(.vertical, 1.0)
			.font(.caption2)
			.background(RoundedRectangle(cornerRadius: 2.0).stroke(color, lineWidth: 1.0))

	}
}

private struct FirmwareRow: View {

	@EnvironmentObject var accessoryManager: AccessoryManager

	@ObservedObject var firmwareFile: FirmwareFile

	var onInstall: (FirmwareFile.FirmwareType, URL) -> Void

	/// ESP32 OTA (BLE/WiFi) requires the AdminMessage.OTAEvent protocol with otaHash,
	/// which was added to Meshtastic firmware in 2.7.18.
	private let minimumESP32OTAVersion = "2.7.18"

	var body: some View {
		HStack(alignment: .center) {
			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 4) {
					switch firmwareFile.firmwareType {
					case .uf2:
						Text("UF2").font(.caption2)
					case .bin:
						Text("BIN").font(.caption2)
					case .otaZip:
						Text("ZIP").font(.caption2)
					}
					Text("\(firmwareFile.versionId)")
						.font(.caption2)
						.foregroundColor(.secondary)
					switch firmwareFile.releaseType {
					case .stable:
						FirmwareTagView("STABLE", color: Color.green)
					case .alpha:
						FirmwareTagView("ALPHA", color: Color.blue)
					case .unlisted:
						FirmwareTagView("UNLISTED", color: Color.orange)
					}
				}
				if firmwareFile.firmwareType == .bin && !accessoryManager.checkIsVersionSupported(forVersion: minimumESP32OTAVersion) {
					FirmwareTagView("Requires \(minimumESP32OTAVersion)+", color: .orange)
				}
			}

			Spacer()

			switch firmwareFile.status {
			case .downloading:
				ProgressView()

			case .downloaded:
				Button {
					onInstall(firmwareFile.firmwareType, firmwareFile.localUrl)
				} label: {
					HStack(alignment: .firstTextBaseline, spacing: 2.0) {
						Text("Install")
						self.installIcon
					}
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
				.disabled(firmwareFile.firmwareType == .bin && !accessoryManager.checkIsVersionSupported(forVersion: minimumESP32OTAVersion))

			case .notDownloaded:
				Button {
					Task {
						try? await firmwareFile.download()
					}
				} label: {
					Text("Download")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
			case .error:
				Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
			}
		}
	}
	
	private var installIcon: Image? {
		switch firmwareFile.firmwareType {
		case .uf2:
			return Image("custom.usb")
		case .bin:
			return nil
		case .otaZip:
			return Image("custom.bluetooth")
		}
	}
}

// MARK: - FirmwareReleaseNotesView

/// Renders GitHub-flavoured markdown release notes using swift-markdown + WKWebView.
struct FirmwareReleaseNotesView: View {
	let markdown: String
	let versionId: String

	var body: some View {
		FirmwareReleaseNotesWebView(html: renderedHTML)
			.navigationTitle(versionId)
			.navigationBarTitleDisplayMode(.inline)
	}

	private var renderedHTML: String {
		let bodyHTML = MarkdownConverter.convert(markdown)
		return """
		<!DOCTYPE html>
		<html>
		<head>
		<meta charset="UTF-8">
		<meta name="viewport" content="width=device-width, initial-scale=1.0">
		<style>
		:root { color-scheme: light dark; }
		body {
			font: -apple-system-body;
			font-size: 15px;
			padding: 16px;
			margin: 0;
			color: var(--text);
			background: var(--bg);
			--text: #1c1c1e;
			--bg: #ffffff;
			--code-bg: #f2f2f7;
			--border: #c6c6c8;
			--link: #007aff;
		}
		@media (prefers-color-scheme: dark) {
			:root {
				--text: #f2f2f7;
				--bg: #1c1c1e;
				--code-bg: #2c2c2e;
				--border: #48484a;
				--link: #0a84ff;
			}
		}
		a { color: var(--link); }
		h1 { font-size: 1.4em; }
		h2 { font-size: 1.2em; }
		h3 { font-size: 1.1em; }
		code {
			background: var(--code-bg);
			padding: 2px 5px;
			border-radius: 4px;
			font-size: 0.9em;
		}
		pre { background: var(--code-bg); padding: 12px; border-radius: 8px; overflow-x: auto; }
		pre code { background: none; padding: 0; }
		table { border-collapse: collapse; width: 100%; margin: 12px 0; }
		th, td { border: 1px solid var(--border); padding: 8px; text-align: left; }
		th { background: var(--code-bg); font-weight: 600; }
		blockquote { border-left: 3px solid var(--border); margin: 12px 0; padding-left: 12px; color: var(--text); opacity: 0.8; }
		ul, ol { padding-left: 24px; }
		li { margin: 4px 0; }
		img { max-width: 100%; }
		.warning-callout, .important-callout, .tips-callout {
			border-radius: 8px;
			padding: 12px 16px;
			margin: 12px 0;
		}
		.warning-callout {
			background: rgba(255, 59, 48, 0.12);
			border-left: 4px solid #ff3b30;
		}
		.important-callout {
			background: rgba(175, 82, 222, 0.12);
			border-left: 4px solid #af52de;
		}
		.tips-callout {
			background: rgba(0, 122, 255, 0.12);
			border-left: 4px solid #007aff;
		}
		</style>
		</head>
		<body>\(bodyHTML)</body>
		</html>
		"""
	}
}

private struct FirmwareReleaseNotesWebView: UIViewRepresentable {
	let html: String

	func makeUIView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = .clear
		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		webView.loadHTMLString(html, baseURL: nil)
	}
}
