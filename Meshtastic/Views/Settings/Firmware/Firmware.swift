//
//  Firmware.swift
//  Meshtastic
//
//   Copyright(c) by Garth Vander Houwen on 3/10/23.
//

import SwiftUI
import StoreKit
import OSLog
import SwiftDraw
import UniformTypeIdentifiers

// 1. THE WRAPPER
// This handles the fetching safely. It does not run logic in init.
struct Firmware: View {
	let node: NodeInfoEntity
	
	// Use SwiftUI's native FetchRequest mechanism
	@FetchRequest var hardwareResults: FetchedResults<DeviceHardwareEntity>
	
	init?(node: NodeInfoEntity?) {
		guard let node = node, let pioEnv = node.myInfo?.pioEnv else { return nil }
		self.node = node
		
		let predicate = NSPredicate(format: "platformioTarget == %@", pioEnv)
		_hardwareResults = FetchRequest(
			entity: DeviceHardwareEntity.entity(),
			sortDescriptors: [],
			predicate: predicate,
			animation: .default
		)
	}
	
	var body: some View {
		if let hardware = hardwareResults.first {
			FirmwareContentView(node: node, hardware: hardware)
		} else {
			// Fallback content
			List {
				Text("Hardware not found for \(node.myInfo?.pioEnv ?? "unknown")")
			}
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
	@State var locallyChosenFirmwareFile: URL? = nil
	
	init(node: NodeInfoEntity, hardware: DeviceHardwareEntity) {
		self.node = node
		self.hardware = hardware
		_firmwareList = StateObject(wrappedValue: FirmwareViewModel(forHardware: hardware))
	}
	
	var body: some View {
		List {
			// SECTION 1: HERO
			Section {
				HStack {
					SupportedHardwareBadge(hwModelId: hardware.hwModel)
					Text("Device Model: \(hardware.displayName ?? "Unknown")")
						.font(.largeTitle)
						.fixedSize(horizontal: false, vertical: true)
				}
				
				VStack {
					FirmwareHeroImage(hardware: hardware)
						.frame(height: 300) // Give List a hint of the height
						.frame(maxWidth: .infinity)
				}
				
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
	}
	
	// MARK: - Subviews
	
	@ViewBuilder
	var firmwareRows: some View {
		switch firmwareSelection {
		case .stable:
			let stables = firmwareList.mostRecentFirmware(forReleaseType: .stable)
			ForEach(stables, id: \.localUrl) { release in
				FirmwareRow(firmwareFile: release)
			}
			if let last = stables.last, let notes = last.releaseNotes {
				NavigationLink("Release Notes") {
					ScrollView { Text(notes).padding() }
						.navigationTitle("\(last.versionId)")
				}
			}
		case .alpha:
			let alphas = firmwareList.mostRecentFirmware(forReleaseType: .alpha)
			ForEach(alphas, id: \.localUrl) { release in
				FirmwareRow(firmwareFile: release)
			}
			if let last = alphas.last, let notes = last.releaseNotes {
				NavigationLink("Release Notes") {
					ScrollView { Text(notes).padding() }
						.navigationTitle("\(last.versionId)")
				}
			}
		case .downloaded:
			let downloads = firmwareList.downloadedFirmware(includeInProgressDownloads: true)
			if downloads.isEmpty {
				Text("No firmware has been downloaded for this device.")
			} else {
				ForEach(downloads, id: \.localUrl) { file in
					FirmwareRow(firmwareFile: file)
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
							self.showInstallationSheet = .bin
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
				Button("Check For Updates") {
					Task.detached {
						try? await meshtasticAPI.refreshFirmwareAPIData()
					}
				}.buttonStyle(.bordered)
				.controlSize(.small)
			}
		}.textCase(nil)
		#else
		HStack {
			Text("Firmware Releases")
			Spacer()
			if meshtasticAPI.isLoadingFirmwareList {
				ProgressView()
			} else {
				Button("Check For Updates") {
					Task.detached {
						try? await meshtasticAPI.refreshFirmwareAPIData()
					}
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
					.frame(width: 300, height: 300)
					.cornerRadius(5)
			} else {
				// Placeholder prevents List jumpiness while loading
				Color.clear
					.frame(width: 300, height: 300)
			}
		}
		.task {
			// Perform the Core Data relationship traversal off the main layout pass
			if svg == nil {
				self.svg = getSVG()
			}
		}
	}
	
	private func getSVG() -> SVG? {
		let images = hardware.images as? Set<DeviceHardwareImageEntity> ?? []
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
			.padding(.horizontal, 4.0)
			.padding(.vertical, 1.0)
			.font(.caption2)
			.background(RoundedRectangle(cornerRadius: 4.0).stroke(color, lineWidth: 1.2))

	}
}

private struct FirmwareRow: View {
	
	@ObservedObject var firmwareFile: FirmwareFile
	
	@State var unsupporedInstallationMessage: Bool = false
	@State var showInstallationSheet: FirmwareFile.FirmwareType?
	
	var body: some View {
		VStack {
			HStack {
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
				
				Spacer()

				switch firmwareFile.status {
				case .downloading:
					ProgressView()
					
				case .downloaded:
					Button {
						switch firmwareFile.firmwareType {
						case .uf2:
							self.showInstallationSheet = .uf2
						case .bin:
							self.showInstallationSheet = .bin
						case .otaZip:
							self.showInstallationSheet = .otaZip
						}
					} label: {
						HStack(alignment: .firstTextBaseline, spacing: 2.0) {
							Text("Install")
								.font(UIDevice.current.userInterfaceIdiom == .phone ? .caption : .body)
							self.installIcon
						}
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(UIDevice.current.userInterfaceIdiom == .phone ? .small : .regular)
					
				case .notDownloaded:
					Button {
						Task {
							try? await firmwareFile.download()
						}
					} label: {
						Text("Download")
							.font(UIDevice.current.userInterfaceIdiom == .phone ? .caption : .body)
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(UIDevice.current.userInterfaceIdiom == .phone ? .small : .regular)
				case .error:
					Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
				}
			}
		}.alert(isPresented: $unsupporedInstallationMessage) {
			Alert(title: Text("Unsupported Installation"),
				  message: Text("Firmware installation is not supported for this device architecture."),
				  dismissButton: .default(Text("OK")))
		}.sheet(item: $showInstallationSheet) { type in
			switch type {
			case .otaZip:
				NRFDFUSheet(firmwareToFlash: firmwareFile.localUrl)
			case .uf2:
				UF2MassStorageView(fileURL: firmwareFile.localUrl)
			case .bin:
				ESP32OTAIntroSheet(binFileURL: firmwareFile.localUrl)
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
