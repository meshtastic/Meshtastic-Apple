//
//  Firmware.swift
//  Meshtastic
//
//   Copyright(c) by Garth Vander Houwen on 3/10/23.
//

import SwiftUI
@preconcurrency import SwiftData
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

	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Query private var hardwareResults: [DeviceHardwareEntity]
	@State private var cachedHardware: DeviceHardwareEntity?
	@State private var cachedNode: NodeInfoEntity?
	@State private var hardwareState = FirmwareHardwareViewState()

	init(node: NodeInfoEntity?) {
		self.node = node
	}

	var body: some View {
		Group {
			if let resolvedNode = cachedNode,
			   let resolvedHardware = cachedHardware,
			   let firmwareTarget = hardwareState.resolution?.firmwareTarget {
				FirmwareContentView(
					node: resolvedNode,
					hardware: resolvedHardware,
					firmwareTarget: firmwareTarget
				)
				.id("\(resolvedNode.num)-\(firmwareTarget)")
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
		.task {
			await refreshFromAPI()
		}
		.onChange(of: hardwareResults) {
			resolveHardware()
		}
		.onChange(of: node?.num) {
			resetHardwareCache()
			resolveHardware()
		}
		.onChange(of: node?.myInfo?.pioEnv) { _, newValue in
			handlePlatformIOTargetChange(to: newValue)
		}
		.onChange(of: node?.user?.hwModelId) {
			resolveHardware()
		}
	}

	/// Pull the hardware catalog and the firmware release list when this screen opens.
	///
	/// The catalog is so a board added since this build shipped resolves by its PlatformIO target
	/// rather than falling back to another board sharing its hardware model. The release list is
	/// because nothing else on this screen fetches it: the rows read whatever is already stored,
	/// and the only other fetch is the launch cascade. If that one failed — an API error, or the
	/// GitHub fallback being rate limited — the screen stayed empty until the user found the
	/// refresh button.
	///
	/// Neither is throttled. Both endpoints send Cache-Control and an ETag, so a repeat call is
	/// served from URLSession's cache or revalidated for an empty 304. The catalog pass skips
	/// images, which are local anyway.
	private func refreshFromAPI() async {
		do {
			try await MeshtasticAPI.shared.refreshDevicesAPIData(includeImages: false)
			resolveHardware()
		} catch {
			Logger.services.warning("Hardware catalog refresh failed: \(error.localizedDescription, privacy: .public)")
		}
		do {
			try await MeshtasticAPI.shared.refreshFirmwareAPIData()
		} catch {
			Logger.services.warning("Firmware list refresh failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func resolveHardware() {
		guard let node else {
			resetHardwareCache()
			return
		}
		let records = hardwareResults.map(HardwareCatalogRecord.init)
		let hwModel = node.user.map { Int64($0.hwModelId) }
		hardwareState.resolve(
			nodeNum: node.num,
			pioEnv: node.myInfo?.pioEnv,
			hwModel: hwModel,
			in: records
		)
		cacheResolvedHardware(for: node)
	}

	private func handlePlatformIOTargetChange(to pioEnv: String?) {
		guard let node else {
			resetHardwareCache()
			return
		}
		let records = hardwareResults.map(HardwareCatalogRecord.init)
		let hwModel = node.user.map { Int64($0.hwModelId) }
		let didReset = hardwareState.handlePlatformIOTargetChange(
			to: pioEnv,
			nodeNum: node.num,
			hwModel: hwModel,
			in: records
		)
		if didReset, hardwareState.resolution == nil {
			if !accessoryManager.otaInProgress {
				cachedNode = nil
				cachedHardware = nil
			}
			return
		}
		cacheResolvedHardware(for: node)
	}

	private func cacheResolvedHardware(for node: NodeInfoEntity) {
		guard let resolution = hardwareState.resolution,
		      let hardware = hardwareResults.first(where: {
			      $0.platformioTarget == resolution.metadataTarget
		      }) else { return }

		// Only update the cache when all data is valid. Relationship faults can momentarily make
		// MyInfo or User nil, but should not replace working firmware content with the empty state.
		cachedNode = node
		cachedHardware = hardware
	}

	private func resetHardwareCache() {
		// An update disconnects the radio on purpose. Keep the cached content on
		// screen through it, or the update sheet is torn down mid-flash and the
		// device is left sitting in its bootloader.
		if accessoryManager.otaInProgress { return }
		cachedNode = nil
		cachedHardware = nil
		hardwareState.reset()
	}
}

// 2. THE CONTENT
// Decoupled from fetching logic.
private struct FirmwareContentView: View {
	
	private enum FirmwareTab {
		case stable, alpha, nightly, downloaded
	}
	
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	
	let node: NodeInfoEntity
	let hardware: DeviceHardwareEntity
	let firmwareTarget: String
	/// The node's LoRa region at the time this view was created; drives
	/// region-aware artifact selection and the locale-variant guidance rows.
	let nodeRegion: RegionCodes

	// We can safely init the StateObject here because 'hardware' is passed in
	@StateObject var firmwareList: FirmwareViewModel
	@State private var firmwareSelection = FirmwareTab.stable
	
	// For Catalyst file picker
	@State var showFirmwareFilePicker = false
	@State var showInstallationSheet: FirmwareFile.FirmwareType?
	@State var locallyChosenFirmwareFile: URL?
	// For row-level install sheet
	@State var rowInstallation: RowInstallation?
	@State var showBootloaderUpgrade = false
	@State var showFactoryErase = false
	@State private var isDownloadingUpdate = false
	@State private var updateDownloadFailed = false
	@State private var showsAdvanced = false

	struct RowInstallation: Identifiable {
		let type: FirmwareFile.FirmwareType
		let url: URL
		var id: String { "\(type.rawValue)-\(url.absoluteString)" }
	}
	
	init(node: NodeInfoEntity, hardware: DeviceHardwareEntity, firmwareTarget: String) {
		self.node = node
		self.hardware = hardware
		self.firmwareTarget = firmwareTarget
		let region = node.loRaConfig.flatMap { RegionCodes(rawValue: Int($0.regionCode)) } ?? .unset
		self.nodeRegion = region
		_firmwareList = StateObject(wrappedValue: FirmwareViewModel(
			forHardware: hardware,
			platformioTarget: firmwareTarget,
			preferredRegion: region
		))
	}
	
	var body: some View {
		List {
			// SECTION 1: THE RADIO — the same card the update screen shows.
			Section {
				VStack(spacing: 14) {
					FirmwareHeroImage(hardware: hardware, pioEnv: node.myInfo?.pioEnv)
						.frame(maxHeight: 160)
						.accessibilityHidden(true)
					VStack(spacing: 4) {
						Text(radioName)
							.font(.title3.bold())
							.multilineTextAlignment(.center)
						if let hardwareName = hardware.displayName, hardwareName != radioName {
							Text(hardwareName)
								.font(.subheadline)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
						}
						SupportedHardwareBadge(hwModelId: hardware.hwModel, inline: true)
					}
					updateStatus
				}
				.padding(.vertical, 8)
				.frame(maxWidth: .infinity)
				// Rounded rectangles, not the default capsule, to match the update screen.
				.buttonBorderShape(.roundedRectangle(radius: 12))
			}

			Section {
				// Details for troubleshooting; the card above already shows the name and version.
				DisclosureGroup(isExpanded: $showsAdvanced) {
					LabeledContent("Platform IO", value: node.myInfo?.pioEnv ?? "Unknown".localized)
					LabeledContent("Architecture", value: hardware.architecture ?? "Unknown".localized)
					LabeledContent("Intended LoRa Region", value: intendedRegionLabel)
				} label: {
					Text("Advanced")
				}
			} footer: {
				if shouldShowRegionUnsetWarning {
					Label("Set a LoRa region before installing firmware.", systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.orange)
				} else if shouldShowLocaleVariantWarning {
					Label("This region may require a locale-specific firmware file for correct on-device text rendering.", systemImage: "character.book.closed.fill")
						.foregroundStyle(.orange)
				}
			}

			// SECTION 2: RELEASES
			Section(header: releasesHeader, footer: lastUpdatedFooter) {
				Picker("Firmware Version", selection: $firmwareSelection) {
					Text("Stable").tag(FirmwareTab.stable)
					Text("Alpha").tag(FirmwareTab.alpha)
					Text("Nightly").tag(FirmwareTab.nightly)
					Text("Downloaded").tag(FirmwareTab.downloaded)
				}.pickerStyle(.segmented)
				
				firmwareRows
			}

			// SECTION 3: BOOTLOADER — nRF52 boards OTAFIX ships a bootloader for.
			// UX gate only; the sheet identifies the board from the drive's own
			// INFO_UF2.TXT before anything is offered for writing.
			if showsMaintenanceSection {
				Section {
					if let bootloaderStatus {
						bootloaderVersionRow(bootloaderStatus)
					}
					if showsBootloaderUpgrade && !(bootloaderStatus?.isUpToDate ?? false) {
						Button {
							showBootloaderUpgrade = true
						} label: {
							Label("Upgrade Bootloader", systemImage: "memorychip")
						}
					}
					Button(role: .destructive) {
						showFactoryErase = true
					} label: {
						Label("Factory Erase", systemImage: "externaldrive.badge.xmark")
					}
				} header: {
					Text("Maintenance")
				} footer: {
					Text("A newer bootloader makes Bluetooth updates more reliable. Factory erase wipes the radio and can bring back one that won't start.", comment: "Firmware Updates: footer under the Maintenance section")
				}
			}
		}
		.navigationTitle("Firmware Updates")
		.navigationBarTitleDisplayMode(.inline)
		.onChange(of: meshtasticAPI.isLoadingFirmwareList) { _, isLoading in
			if !isLoading {
				firmwareList.refresh()
			}
		}
		.hostedSheet(isPresented: $showBootloaderUpgrade) {
			BootloaderUpgradeView(platformioTarget: firmwareTarget)
				.environment(\.firmwareUpdateRadio, maintenanceRadio)
		}
		.hostedSheet(isPresented: $showFactoryErase) {
			FactoryEraseView()
				.environment(\.firmwareUpdateRadio, maintenanceRadio)
		}
		.hostedSheet(item: $rowInstallation) { installation in
			// UF2MassStorageView is left unnamed here and below: reflection already names it,
			// and a second name would split its history in Error Tracking.
			switch installation.type {
			case .otaZip:
				NRFDFUSheet(firmwareToFlash: installation.url, bootloaderAdvice: nrfBootloaderAdvice, platformioTarget: firmwareTarget)
					.environment(\.firmwareUpdateRadio, updateRadio(for: installation.url))
					.trackScreen(.nordicDFUUpdate)
					// An update has to keep running and can't be backed out of mid-transfer, which a page
					// on the cinema screen can't promise; it runs in the app window.
					.hostedWindowOnly()
			case .uf2:
				UF2MassStorageView(fileURL: installation.url)
					.environment(\.firmwareUpdateRadio, updateRadio(for: installation.url))
			case .bin:
				ESP32OTAIntroSheet(binFileURL: installation.url)
					.environment(\.firmwareUpdateRadio, updateRadio(for: installation.url))
					.trackScreen(.esp32Update)
										.hostedWindowOnly()
			}
		}
	}
	
	// MARK: - Subviews

	/// The radio's own name, falling back to the hardware's.
	private var radioName: String {
		let longName = node.user?.longName ?? ""
		return longName.isEmpty ? (hardware.displayName ?? "") : longName
	}

	/// The newest stable file this page would install with one tap: the Bluetooth DFU zip on
	/// nRF52, the OTA bin on ESP32, the UF2 on RP2040.
	private var latestStableFile: FirmwareFile? {
		guard let architecture = hardware.architecture.flatMap({ Architecture(rawValue: $0) }) else { return nil }
		let type = FirmwareUpdatePlan.phoneUpdateFileType(for: architecture) ?? .uf2
		return firmwareList.mostRecentFirmware(forReleaseType: .stable).first { $0.firmwareType == type }
	}

	/// The version the radio runs against the latest stable, with Update when it's behind.
	@ViewBuilder
	private var updateStatus: some View {
		let current = node.metadata?.firmwareVersion
		if let current, !current.isEmpty {
			Text("Firmware \(FirmwareUpdateNotificationPolicy.normalizedVersion(current))", comment: "The firmware version the radio runs, on the Firmware Updates card")
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
		if let current, !current.isEmpty, let file = latestStableFile,
		   file.status != .unavailable,
		   FirmwareUpdateNotificationPolicy.isUpdateAvailable(current: current, latestStable: file.versionId) {
			VStack(spacing: 10) {
				Text("Stable \(FirmwareUpdateNotificationPolicy.normalizedVersion(file.versionId)) is available.", comment: "Firmware Updates card when the radio is behind the latest stable release; the version")
					.font(.callout)
					.multilineTextAlignment(.center)
				if updateDownloadFailed {
					Text("Couldn't download the firmware. Check your internet connection and try again.")
						.font(.footnote)
						.foregroundStyle(.red)
						.multilineTextAlignment(.center)
				}
				Button {
					Task { await installLatestStable(file) }
				} label: {
					HStack(spacing: 6) {
						if isDownloadingUpdate {
							ProgressView()
								.controlSize(.small)
							Text("Downloading")
						} else {
							Text("Update")
						}
					}
					.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.tint(.accentFill)
				.controlSize(.large)
				.disabled(isDownloadingUpdate)
			}
			.padding(.top, 4)
		} else if latestStableFile != nil, current?.isEmpty == false {
			Label {
				Text("Up to date with the latest stable release", comment: "Firmware Updates card when the radio runs the latest stable release or newer")
			} icon: {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.green)
			}
			.font(.callout)
		}
	}

	/// Downloads the file if needed, then opens the update screen for it.
	private func installLatestStable(_ file: FirmwareFile) async {
		isDownloadingUpdate = true
		updateDownloadFailed = false
		defer { isDownloadingUpdate = false }
		do {
			if file.status != .downloaded {
				try await file.download()
			}
			rowInstallation = RowInstallation(type: file.firmwareType, url: file.localUrl)
		} catch is CancellationError {
		} catch {
			updateDownloadFailed = true
		}
	}

	/// The radio as the bootloader and erase screens show it: no firmware going on.
	private var maintenanceRadio: FirmwareUpdateRadio {
		let longName = node.user?.longName ?? ""
		return FirmwareUpdateRadio(
			hardware: hardware,
			pioEnv: node.myInfo?.pioEnv,
			name: longName.isEmpty ? (hardware.displayName ?? "") : longName,
			firmwareVersion: nil
		)
	}

	/// The radio as the update screen shows it: its picture, its own name, and the version
	/// read from the firmware file's name.
	private func updateRadio(for firmwareFile: URL) -> FirmwareUpdateRadio {
		let longName = node.user?.longName ?? ""
		return FirmwareUpdateRadio(
			hardware: hardware,
			pioEnv: node.myInfo?.pioEnv,
			name: longName.isEmpty ? (hardware.displayName ?? "") : longName,
			firmwareVersion: FirmwareFileVersion.version(in: firmwareFile.lastPathComponent),
			firmwareBuild: FirmwareFileVersion.build(in: firmwareFile.lastPathComponent)
		)
	}
	
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
		case .nightly:
			let nightlies = firmwareList.mostRecentFirmware(forReleaseType: .nightly)
			if nightlies.isEmpty {
				Text("No nightly build is available for this device right now.")
			} else {
				ForEach(nightlies, id: \.localUrl) { release in
					FirmwareRow(firmwareFile: release) { type, url in
						self.rowInstallation = RowInstallation(type: type, url: url)
					}
				}
				if let last = nightlies.last, let notes = last.releaseNotes {
					NavigationLink("Release Notes") {
						FirmwareReleaseNotesView(markdown: notes, versionId: last.versionId)
					}
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
	
	var intendedRegionLabel: String {
		"\(nodeRegion.description) (\(nodeRegion.topic))"
	}

	var shouldShowRegionUnsetWarning: Bool {
		nodeRegion == .unset
	}

	var shouldShowLocaleVariantWarning: Bool {
		nodeRegion.prefersLocalizedFontFirmware
	}

	/// Whether to offer the OTAFIX bootloader upgrade: nRF52 hardware whose
	/// product OTAFIX lists as supported. Deciding which image to write happens
	/// in the sheet, from the Board-ID on the device's own drive.
	var showsMaintenanceSection: Bool {
		hardware.architecture.flatMap { Architecture(rawValue: $0) } == .nrf52840
	}

	/// OTAFIX ships bootloaders for a subset of nRF52 products; factory erase works on
	/// any Adafruit-family bootloader, so only the upgrade button carries this gate.
	var showsBootloaderUpgrade: Bool {
		OTAFIXBootloader.supportsTarget(firmwareTarget)
	}

	/// Whether a failed Bluetooth update should point at the Meshtastic bootloader: nRF52 boards
	/// with an OTAFIX build, whose bootloader is older than 2.6.0 or unreported.
	var nrfBootloaderAdvice: BootloaderAdvice? {
		guard showsMaintenanceSection else { return nil }
		return BootloaderAdvice.forNRF52(packed: node.metadata?.bootloaderVersion, upgradeAvailable: showsBootloaderUpgrade)
	}

	/// The bootloader the radio reports, against the latest release. Nil when it reports none
	/// (older firmware), and then the section is as it was before the field existed.
	var bootloaderStatus: BootloaderStatus? {
		guard let packed = node.metadata?.bootloaderVersion,
			  let value = UInt32(exactly: packed) else { return nil }
		return BootloaderStatus(packed: value, latestTag: MaintenanceUf2ManifestStore.shared.releaseTag)
	}

	func bootloaderVersionRow(_ status: BootloaderStatus) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			VStack(alignment: .leading, spacing: 2) {
				Text("Current Bootloader Version").font(.caption).foregroundColor(.secondary)
				switch status.installed {
				case .olderThanFirstReported:
					Text("Older than \(BootloaderVersion.firstReported.description)")
				case .version(let version):
					Text(verbatim: version.description)
				}
			}
			.accessibilityElement(children: .combine)
			if let latest = status.latest {
				VStack(alignment: .leading, spacing: 2) {
					Text("Latest Bootloader Version").font(.caption).foregroundColor(.secondary)
					if status.isUpToDate {
						Text("\(latest.description), up to date")
					} else {
						Text(verbatim: latest.description)
					}
				}
				.accessibilityElement(children: .combine)
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
			}.hostedSheet(item: $showInstallationSheet) { type in
				if let locallyChosenFirmwareFile = self.locallyChosenFirmwareFile {
					switch type {
					case .otaZip:
						NRFDFUSheet(firmwareToFlash: locallyChosenFirmwareFile, bootloaderAdvice: nrfBootloaderAdvice, platformioTarget: firmwareTarget)
							.environment(\.firmwareUpdateRadio, updateRadio(for: locallyChosenFirmwareFile))
							.trackScreen(.nordicDFUUpdate)
							// An update has to keep running and can't be backed out of mid-transfer, which a page
							// on the cinema screen can't promise; it runs in the app window.
							.hostedWindowOnly()
					case .uf2:
						UF2MassStorageView(fileURL: locallyChosenFirmwareFile)
							.environment(\.firmwareUpdateRadio, updateRadio(for: locallyChosenFirmwareFile))
					case .bin:
						ESP32OTAIntroSheet(binFileURL: locallyChosenFirmwareFile)
							.environment(\.firmwareUpdateRadio, updateRadio(for: locallyChosenFirmwareFile))
							.trackScreen(.esp32Update)
														.hostedWindowOnly()
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
				.accessibilityLabel(String(localized: "Refresh firmware list", comment: "VoiceOver label for the refresh firmware list button"))
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
				.accessibilityLabel(String(localized: "Refresh firmware list", comment: "VoiceOver label for the refresh firmware list button"))
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
	var pioEnv: String?
	@State private var svg: SVG?
	@State private var resolved = false
	// One height for the image and its placeholder so the row doesn't jump when
	// resolution finishes.
	private static let heroHeight: CGFloat = 140

	var body: some View {
		Group {
			if let svg = svg {
				SVGView(svg: svg)
					.resizable()
					.scaledToFit()
					.cornerRadius(5)
					.frame(maxWidth: .infinity, maxHeight: Self.heroHeight)
			} else if !resolved {
				// Placeholder prevents List jumpiness while loading. Once resolution has
				// run and found nothing, render nothing so the row collapses instead of
				// holding an image-sized hole in the layout.
				Color.clear
					.frame(height: Self.heroHeight)
			}
		}
		.task(id: pioEnv) {
			// Perform the Core Data relationship traversal off the main layout pass.
			// Keyed on pioEnv: the radio reports its PlatformIO env after connect, so
			// resolution must rerun when it arrives or changes.
			svg = getSVG()
			resolved = true
		}
	}
	
	private func getSVG() -> SVG? {
		// The radio's own PlatformIO env wins when an image with that exact name ships,
		// so a product like the WisMesh Pocket can get its own art without a catalog change.
		if let pioEnv, !pioEnv.isEmpty,
		   let data = Self.bundledImageData(named: "\(pioEnv).svg"),
		   let svg = SVG(data: data) {
			return svg
		}
		if let image = hardware.images.first,
		   let data = image.svgData,
		   let svg = SVG(data: data) {
			return svg
		}
		// The synced image entities only exist after a catalog pass, which is throttled to
		// once every two days. The bundle carries the catalog images named by hardware-model
		// slug, so a fresh install can still show the radio without waiting for a sync.
		if let slug = hardware.hwModelSlug, !slug.isEmpty,
		   let data = Self.bundledImageData(named: "\(slug.lowercased()).svg"),
		   let svg = SVG(data: data) {
			return svg
		}
		return nil
	}
	
	static func bundledImageData(named name: String) -> Data? {
		let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "images")
			?? Bundle.main.url(forResource: name, withExtension: nil)
		return url.flatMap { try? Data(contentsOf: $0) }
	}
}

struct FirmwareTagView: View {
	// LocalizedStringKey, not String: a String argument reaches Text() already resolved,
	// so the tag literals were never extracted for translation.
	let text: LocalizedStringKey
	let color: Color
	init(_ text: LocalizedStringKey, color: Color = .black) {
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
					case .nightly:
						FirmwareTagView("NIGHTLY", color: Color.purple)
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
				.buttonBorderShape(.roundedRectangle(radius: 8))
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
				.buttonBorderShape(.roundedRectangle(radius: 8))
				.controlSize(.small)
			case .unavailable:
				Text("Not built for this device")
					.font(.caption2)
					.foregroundColor(.secondary)

			case .error:
				Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
			}
		}
		.task {
			await firmwareFile.checkAvailability()
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
