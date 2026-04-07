//
//  TAKServerConfig.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import SwiftUI
import UniformTypeIdentifiers
import OSLog
import CoreData

enum CertificateImportType {
	case p12
	case pem
}

struct TAKServerConfig: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(keyPath: \ChannelEntity.index, ascending: true)],
		predicate: NSPredicate(format: "role > 0"),
		animation: .default
	) private var channels: FetchedResults<ChannelEntity>

	@StateObject private var takServer = TAKServerManager.shared
	@Environment(\.dismiss) private var dismiss
	@State private var showingFileImporter = false
	@State private var importType: CertificateImportType = .p12
	@State private var p12Password = ""
	@State private var showingPasswordPrompt = false
	@State private var pendingP12Data: Data?
	@State private var importError: String?
	@State private var showingImportError = false
	@State private var showingFileExporter = false
	@State private var dataPackageURL: URL?
	@State private var showingFixWarning = false
	@State private var isFixingChannel = false
	@State private var showShareChannels = false
	@State private var showShareChannelsAlert = false
	@State private var connectedNode: NodeInfoEntity?
	@State private var isWarningExpanded = true

	private let certManager = TAKCertificateManager.shared

	var body: some View {
		Form {
			if !takServer.primaryChannelIssues.isEmpty {
				primaryChannelWarningSection
			}
			serverStatusSection
			serverConfigSection
			certificatesSection
			dataPackageSection
		}
		.navigationTitle("TAK Server")
		.onAppear {
			takServer.checkPrimaryChannelValidity()
			if let nodeNum = accessoryManager.activeDeviceNum {
				connectedNode = getNodeInfo(id: nodeNum, context: context)
			}
		}
		.alert("Fix Primary Channel?", isPresented: $showingFixWarning) {
			Button("Cancel", role: .cancel) {}
			Button("Fix Channel", role: .destructive) {
				fixPrimaryChannel()
			}
		} message: {
			Text("This will change your primary channel to:\n• Name: TAK\n• Encryption: New 256-bit AES key\n• LoRa preset: Short Fast (recommended for TAK)\n\nThis is required for TAK Server to work properly. Any existing channel sharing links will become invalid.")
		}
		.fileImporter(
			isPresented: $showingFileImporter,
			allowedContentTypes: importType == .p12 ? [UTType(filenameExtension: "p12") ?? .pkcs12, .pkcs12] : [UTType(filenameExtension: "pem") ?? .plainText],
			allowsMultipleSelection: false
		) { result in
			switch importType {
			case .p12:
				handleP12Import(result)
			case .pem:
				handlePEMImport(result)
			}
		}
		.alert("Enter P12 Password", isPresented: $showingPasswordPrompt) {
			SecureField("Password", text: $p12Password)
			Button("Import") {
				importP12WithPassword()
			}
			Button("Cancel", role: .cancel) {
				p12Password = ""
				pendingP12Data = nil
			}
		} message: {
			Text("Enter the password for the PKCS#12 file")
		}
		.alert("Import Error", isPresented: $showingImportError) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(importError ?? "Unknown error")
		}
		.alert("Channel Fixed!", isPresented: $showShareChannelsAlert) {
			Button("Share with TAK Buddies") {
				showShareChannels = true
			}
			Button("Later", role: .cancel) {}
		} message: {
			Text("Your channel has been configured for TAK. To share the QR code: go to Settings > Share QR Code")
		}
		.fileExporter(
			isPresented: $showingFileExporter,
			document: dataPackageURL.map { ZipDocument(url: $0) },
			contentType: .zip,
			defaultFilename: "Meshtastic_TAK_Server.zip"
		) { result in
			switch result {
			case .success(let url):
				Logger.tak.info("Data package saved to: \(url.path)")
			case .failure(let error):
				importError = "Failed to save: \(error.localizedDescription)"
				showingImportError = true
			}
			// Clean up the source file
			if let sourceURL = dataPackageURL {
				try? FileManager.default.removeItem(at: sourceURL)
			}
			dataPackageURL = nil
		}
		.navigationDestination(isPresented: $showShareChannels) {
			if let node = connectedNode {
				ShareChannels(node: node)
			}
		}
	}

	// MARK: - Primary Channel Warning Section

	private var primaryChannelWarningSection: some View {
		Section {
			DisclosureGroup(isExpanded: $isWarningExpanded) {
				VStack(alignment: .leading, spacing: 12) {
					if takServer.readOnlyMode {
						Text("Your primary channel is using the default settings (no name or default encryption key). TAK Server is running in read-only mode.")
							.font(.subheadline)
							.foregroundColor(.secondary)
					}

					Text("You can fix this yourself by changing your primary channel:")
						.font(.subheadline)

					VStack(alignment: .leading, spacing: 4) {
						Label("Set a channel name", systemImage: "1.circle.fill")
						Label("Use a 256-bit encryption key", systemImage: "2.circle.fill")
					}
					.font(.caption)
					.foregroundColor(.secondary)

					Divider()

					Button {
						showingFixWarning = true
					} label: {
						Label("Auto-Fix Channel", systemImage: "wand.and.stars")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)
					.disabled(isFixingChannel)

					Text("Or fix it yourself in Channels settings, then return here.")
						.font(.caption)
						.foregroundColor(.secondary)
						.multilineTextAlignment(.center)
						.frame(maxWidth: .infinity)
				}
				.padding(.vertical, 8)
			} label: {
				HStack {
					Image(systemName: "exclamationmark.triangle.fill")
						.foregroundColor(.orange)
					Text("TAK Cannot Be Used on Public Channel")
						.font(.headline)
				}
			}
		} header: {
			Text("Warning")
		}
	}

	// MARK: - Server Status Section

	private var serverStatusSection: some View {
		Section {
			HStack {
				Label {
					Text("Status")
				} icon: {
					Circle()
						.fill(takServer.isRunning ? .green : .gray)
						.frame(width: 10, height: 10)
				}
				Spacer()
				Text(takServer.statusDescription)
					.foregroundColor(.secondary)
			}

			if let error = takServer.lastError {
				HStack {
					Image(systemName: "exclamationmark.triangle.fill")
						.foregroundColor(.orange)
					Text(error)
						.font(.caption)
						.foregroundColor(.orange)
				}
			}

			if let node = connectedNode,
			   let role = node.user?.role,
			   let deviceRole = DeviceRoles(rawValue: Int(role)),
			   deviceRole != .tak && deviceRole != .takTracker {
				HStack {
					Image(systemName: "exclamationmark.triangle.fill")
						.foregroundColor(.orange)
					Text("Device role is \"\(deviceRole.name)\". Consider setting to TAK or TAK Tracker for optimal operation.")
						.font(.caption)
						.foregroundColor(.orange)
				}
			}
		} header: {
			Text("Server Status")
		}
	}

	// MARK: - Server Configuration Section

	private var serverConfigSection: some View {
		Section {
			Toggle(isOn: $takServer.enabled) {
				Label("Enable TAK Server", systemImage: "antenna.radiowaves.left.and.right")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			HStack {
				Label("Port", systemImage: "number")
				Spacer()
				Text("8089")
					.foregroundColor(.secondary)
			}

			HStack {
				Label("Security", systemImage: "lock.fill")
				Spacer()
				Text("mTLS")
					.foregroundColor(.secondary)
			}

			Toggle(isOn: $takServer.userReadOnlyMode) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Read-Only Mode")
					Text("Meshtastic -> TAK works, TAK -> Meshtastic blocked")
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))
			.disabled(takServer.readOnlyMode)

			Toggle(isOn: $takServer.meshToCotEnabled) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Mesh to CoT Converter")
					Text("Bridge Meshtastic positions, nodes, waypoints, and messages to TAK/CoT format")
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))
			if !channels.isEmpty {
				Picker(selection: $takServer.channel) {
					ForEach(channels, id: \.index) { channel in
						channelLabel(channel)
							.tag(Int(channel.index))
					}
				} label: {
					Label("TAK Channel Index", systemImage: "bubble.left.and.bubble.right")
				}
			}

			if takServer.isRunning {
				Button {
					Task {
						try? await takServer.restart()
					}
				} label: {
					Label("Restart Server", systemImage: "arrow.clockwise")
				}
			}
		} header: {
			Text("Configuration")
		} footer: {
			Text("Secure mTLS connection on port 8089. Both server and client certificates are required. TAK Channel Index selects the channel index where TAK messages will be sent.")
		}
	}

	// MARK: - Certificates Section

	private var certificatesSection: some View {
		Section {
			// Server Certificate
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Label("Server Certificate", systemImage: "key.fill")
					Spacer()
					if certManager.hasServerCertificate() {
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.green)
					} else {
						Image(systemName: "xmark.circle.fill")
							.foregroundColor(.red)
					}
				}

				if let certInfo = certManager.getServerCertificateInfo() {
					Text(certInfo)
						.font(.caption)
						.foregroundColor(.secondary)
				}

				HStack {
					Button {
						importType = .p12
						showingFileImporter = true
					} label: {
						Text("Import Custom .p12")
					}
					.buttonStyle(.bordered)

					if certManager.hasCustomServerCertificate() {
						Button {
							certManager.resetToDefaultServerCertificate()
						} label: {
							Text("Reset to Default")
						}
						.buttonStyle(.bordered)
					}
				}
			}
			.padding(.vertical, 4)

			// Client CA Certificate
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Label("Client CA Certificate", systemImage: "person.badge.shield.checkmark")
					Spacer()
					if certManager.hasClientCACertificate() {
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.green)
					} else {
						Image(systemName: "xmark.circle.fill")
							.foregroundColor(.red)
					}
				}

				let caInfo = certManager.getClientCACertificateInfo()
				if !caInfo.isEmpty {
					ForEach(caInfo, id: \.self) { info in
						Text(info)
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}

				HStack {
					Button {
						importType = .pem
						showingFileImporter = true
					} label: {
						Text(certManager.hasClientCACertificate() ? "Add CA" : "Import .pem")
					}
					.buttonStyle(.bordered)

					if certManager.hasClientCACertificate() {
						Button(role: .destructive) {
							certManager.deleteClientCACertificates()
						} label: {
							Text("Delete All")
						}
						.buttonStyle(.bordered)
					}
				}
			}
			.padding(.vertical, 4)

			// Reset to bundled defaults
			Button {
				certManager.reloadBundledCertificates()
				if takServer.isRunning {
					Task {
						try? await takServer.restart()
					}
				}
			} label: {
				Label("Reload Bundled Certificates", systemImage: "arrow.triangle.2.circlepath")
			}
		} header: {
			Text("TLS Certificates")
		} footer: {
			Text("A default self-signed certificate is included for localhost connections. Import a custom .p12 if needed. Client CA (.pem) validates connecting TAK clients.")
		}
	}

	// MARK: - Data Package Section

	private var dataPackageSection: some View {
		Section {
			Button {
				generateAndShareDataPackage()
			} label: {
				Label("Download TAK Server Data Package", systemImage: "arrow.down.doc.fill")
			}
		} header: {
			Text("Client Configuration")
		} footer: {
			Text("Generate a data package (.zip) to configure TAK clients to connect to this server.")
		}
	}

	// MARK: - Channel Label
	@ViewBuilder
	private func channelLabel(_ channel: ChannelEntity) -> some View {
		if channel.name?.isEmpty ?? false {
			if channel.role == 1 {
				Text(String("PrimaryChannel").camelCaseToWords())
			} else {
				Text(String("Channel \(channel.index)").camelCaseToWords())
			}
		} else {
			Text(String(channel.name ?? "Channel \(channel.index)").camelCaseToWords())
		}
	}

	// MARK: - Import Handlers

	private func handleP12Import(_ result: Result<[URL], Error>) {
		switch result {
		case .success(let urls):
			guard let url = urls.first else { return }

			guard url.startAccessingSecurityScopedResource() else {
				importError = "Cannot access file"
				showingImportError = true
				return
			}
			defer { url.stopAccessingSecurityScopedResource() }

			do {
				pendingP12Data = try Data(contentsOf: url)
				p12Password = ""
				showingPasswordPrompt = true
			} catch {
				importError = "Failed to read file: \(error.localizedDescription)"
				showingImportError = true
			}

		case .failure(let error):
			importError = error.localizedDescription
			showingImportError = true
		}
	}

	private func importP12WithPassword() {
		guard let data = pendingP12Data else { return }

		do {
			_ = try certManager.importServerIdentity(from: data, password: p12Password)
			Logger.tak.info("Server certificate imported successfully")
		} catch {
			importError = error.localizedDescription
			showingImportError = true
		}

		p12Password = ""
		pendingP12Data = nil
	}

	private func handlePEMImport(_ result: Result<[URL], Error>) {
		switch result {
		case .success(let urls):
			guard let url = urls.first else { return }

			guard url.startAccessingSecurityScopedResource() else {
				importError = "Cannot access file"
				showingImportError = true
				return
			}
			defer { url.stopAccessingSecurityScopedResource() }

			do {
				let data = try Data(contentsOf: url)
				_ = try certManager.importClientCACertificate(from: data)
				Logger.tak.info("Client CA certificate imported successfully")
			} catch {
				importError = error.localizedDescription
				showingImportError = true
			}

		case .failure(let error):
			importError = error.localizedDescription
			showingImportError = true
		}
	}

	private func fixPrimaryChannel() {
		isFixingChannel = true
		Task {
			let success = await takServer.autoFixPrimaryChannel()
			await MainActor.run {
				isFixingChannel = false
				if success {
					takServer.userReadOnlyMode = false
					showShareChannelsAlert = true
				} else {
					importError = "Failed to fix primary channel. Make sure you are connected to a device."
					showingImportError = true
				}
			}
		}
	}

	// MARK: - Data Package Generation

	private func generateAndShareDataPackage() {
		guard let url = TAKDataPackageGenerator.shared.generateDataPackage(
			port: TAKServerManager.defaultTLSPort,
			useTLS: true,
			description: "Meshtastic TAK Server"
		) else {
			importError = "Failed to generate data package"
			showingImportError = true
			return
		}

		dataPackageURL = url
		showingFileExporter = true
	}
}

// MARK: - Zip Document for File Exporter

struct ZipDocument: FileDocument {
	static var readableContentTypes: [UTType] { [.zip] }

	let data: Data

	init(url: URL) {
		self.data = (try? Data(contentsOf: url)) ?? Data()
	}

	init(configuration: ReadConfiguration) throws {
		self.data = configuration.file.regularFileContents ?? Data()
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}
