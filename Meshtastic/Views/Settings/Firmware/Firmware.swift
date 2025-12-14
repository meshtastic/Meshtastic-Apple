//
//  Firmware.swift
//  Meshtastic
//
//   Copyright(c) by Garth Vander Houwen on 3/10/23.
//

import SwiftUI
import StoreKit
import OSLog

struct Firmware: View {
	
	private enum FirmwareTab {
		case stable
		case alpha
		case downloaded
	}
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	let node: NodeInfoEntity
	let hardware: DeviceHardwareEntity
	@State var minimumVersion = "2.6.11"
	@State var version = ""
	@State private var currentDevice: DeviceHardware?
	
	@State private var firmwareSelection = FirmwareTab.stable
	
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	
	@StateObject var firmwareList: FirmwareViewModel
	
	init?(node: NodeInfoEntity?) {
		guard let node else { return nil }
		self.node = node
		
		let fetchRequest = DeviceHardwareEntity.fetchRequest()
		guard let pioEnv = node.myInfo?.pioEnv else { return nil }
		fetchRequest.predicate = NSPredicate(format: "platformioTarget == %@", pioEnv)
		fetchRequest.fetchLimit = 1
		
		// Can't use the @Environment because we don't have self yet.
		let context = PersistenceController.shared.container.viewContext
		guard let result = try? context.fetch(fetchRequest).first else {
			return nil
		}
		hardware = result
		_firmwareList = StateObject(wrappedValue: FirmwareViewModel(forHardware: result))
	}
	
	var myVersion: String? {
		return node.metadata?.firmwareVersion
	}
	
	@ViewBuilder
	var firmwareLastUpdatedFooter: some View {
		HStack(alignment: .firstTextBaseline, spacing: 0.0) {
			if self.meshtasticAPI.isLoadingFirmwareList {
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

	@ViewBuilder
	var fimwareReleasesHeader: some View {
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
					Text("Check For Updates")
				}
			}
		}
	}
	
	@StateObject private var dfuViewModel = DFUViewModel()
	
	var body: some View {
		List {
			// Hero image of the node
			Section {
				HStack {
					SupportedHardwareBadge(hwModelId: hardware.hwModel)
					Text("Device Model: \(hardware.displayName ?? "Unknown")")
						.font(.largeTitle)
						.fixedSize(horizontal: false, vertical: true)
				}
				VStack(alignment: .center) {
					DeviceHardwareImage(hwId: node.user?.hwModelId ?? 0)
						.frame(width: 300, height: 300)
						.cornerRadius(5)
				}.frame(maxWidth: .infinity) // Make sure the center is honored by filling the width
				VStack(alignment: .leading) {
					Text("Platform IO").font(.caption).foregroundColor(.secondary)
					Text("\(node.myInfo?.pioEnv, default: "Unknown")")
				}
				VStack(alignment: .leading) {
					Text("Architecture").font(.caption).foregroundColor(.secondary)
					Text("\(self.hardware.architecture, default: "Unknown")")
				}
				VStack(alignment: .leading) {
					Text("Current Firmware Version").font(.caption).foregroundColor(.secondary)
					Text("\(self.myVersion, default: "Unknown")")
				}
			}.listRowSeparator(.hidden)     // Hides lines between rows

			Section(header: self.fimwareReleasesHeader, footer: self.firmwareLastUpdatedFooter) {
				Picker("Firmware Version", selection: $firmwareSelection) {
					Text("Stable").tag(FirmwareTab.stable)
					Text("Alpha").tag(FirmwareTab.alpha)
					Text("Downloaded").tag(FirmwareTab.downloaded)
				}.pickerStyle(.segmented)
				
				switch firmwareSelection {
				case .stable:
					let stables = firmwareList.mostRecentFirmware(forReleaseType: .stable)
					ForEach(stables, id: \.localUrl) { release in
						FirmwareRow(firmwareFile: release)
					}
					if let lastStable = stables.last, let notes = lastStable.releaseNotes {
						NavigationLink {
							ScrollView {
								Text(notes)
									.padding()
							}.navigationTitle("\(lastStable.versionId, default: "ReleaseNotes")")
						} label: {
							Text("Release Notes")
						}
					}
				case .alpha:
					let alphas = firmwareList.mostRecentFirmware(forReleaseType: .alpha)
					ForEach(alphas, id: \.localUrl) { release in
						FirmwareRow(firmwareFile: release)
					}
					if let lastAlpha = alphas.last, let notes = lastAlpha.releaseNotes {
						NavigationLink {
							ScrollView {
								Text(notes)
									.padding()
							}.navigationTitle("\(lastAlpha.versionId, default: "ReleaseNotes")")
						} label: {
							Text("Release Notes")
						}
					}
				case .downloaded:
					let downloadedFirmware = firmwareList.downloadedFirmware(includeInProgressDownloads: true)
					if downloadedFirmware.count > 0 {
						ForEach(downloadedFirmware, id: \.localUrl) { firmwareFile in
							FirmwareRow(firmwareFile: firmwareFile)
						}.onDelete { offsets in
							let filesToDelete = offsets.map { downloadedFirmware[$0] }
							firmwareList.delete(filesToDelete)
						}
					} else {
						Text("No firmware has been downloaded for this device.")
					}
				}
			}
			.navigationTitle("Firmware Updates")
			.navigationBarTitleDisplayMode(.inline)
		}
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
			.padding(.vertical, 2.0)
			.font(.footnote)
			.background(RoundedRectangle(cornerRadius: 4.0).stroke(color, lineWidth: 1.5))

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
							self.unsupporedInstallationMessage = true
						case .otaZip:
							self.showInstallationSheet = .otaZip
						}
					} label: {
						HStack(alignment: .firstTextBaseline, spacing: 2.0) {
							Text("Install")
							self.installIcon
						}
					}.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.regular)
					.padding(2.0)
					
				case .notDownloaded:
					Button {
						Task {
							try? await firmwareFile.download()
						}
					} label: {
						Text("Download")
					}.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.regular)
					.padding(2.0)
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
				ESP32DFUSheet()
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
