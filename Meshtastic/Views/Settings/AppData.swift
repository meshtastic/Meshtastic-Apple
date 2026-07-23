//
//  AppData.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/8/24.
//

import SwiftUI
import OSLog
import SwiftData
import Foundation
import UniformTypeIdentifiers

struct AppData: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var documentsFiles = [URL]()
	@State private var applicationSupportFiles = [URL]()
	@State private var exportDocument = BinaryFileDocument(data: Data())
	@State private var exportFilename = ""
	@State private var exportContentType: UTType = .data
	@State private var isExporting = false
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	private var activeDatabaseFiles: [URL] {
		applicationSupportFiles.filter(isActiveDatabaseFile)
	}

	private var nonDatabaseApplicationSupportFiles: [URL] {
		applicationSupportFiles.filter { !isActiveDatabaseFile($0) }
	}

	private var activeDatabaseTotalSize: Int64 {
		activeDatabaseFiles.reduce(0) { $0 + Int64($1.fileSize) }
	}

	var body: some View {

		VStack {

			Section(header: Text("Phone GPS")) {
				GPSStatus()
			}
			Divider()

			// Map Data Section
			Section(header: Text("Map Data")) {
				NavigationLink(destination: MapDataFiles()) {
					HStack {
						Image(systemName: "map")
							.symbolRenderingMode(.hierarchical)
							.font(idiom == .phone ? .callout : .title)
							.frame(width: 35)

						VStack(alignment: .leading) {
							Text(NSLocalizedString("Upload Map Data", comment: "Title for map data upload screen"))
								.font(.headline)
							Text(NSLocalizedString("Manage custom map overlays", comment: "Subtitle for map data management"))
								.font(.caption)
								.foregroundColor(.secondary)
						}

						Spacer()

						Image(systemName: "chevron.right")
							.font(.caption)
							.foregroundColor(.secondary)
					}
					.padding(.horizontal)
					.padding(.vertical, 4)
					.accessibilityElement(children: .combine)
				}
			}
			Divider()
		}

		List {
			if !activeDatabaseFiles.isEmpty {
				Section(header: Text("Active Database")) {
					databaseSizeRow(title: "Store", fileName: "Meshtastic.store")
					databaseSizeRow(title: "WAL", fileName: "Meshtastic.store-wal")
					databaseSizeRow(title: "SHM", fileName: "Meshtastic.store-shm")
					LabeledContent("Total", value: ByteCountFormatter.string(fromByteCount: activeDatabaseTotalSize, countStyle: .file))
				}
			}

			if !nonDatabaseApplicationSupportFiles.isEmpty {
				Section(header: Text("Application Support")) {
					ForEach(nonDatabaseApplicationSupportFiles, id: \.self) { file in
						fileRow(file)
					}
				}
			}

			if !documentsFiles.isEmpty {
				Section(header: Text("Documents")) {
					ForEach(documentsFiles, id: \.self) { file in
						fileRow(file)
					}
				}
			}
		}
		.navigationBarTitle("File Storage", displayMode: .inline)
		.onAppear(perform: {
			loadFiles()
		})
		.fileExporter(
			isPresented: $isExporting,
			document: exportDocument,
			contentType: exportContentType,
			defaultFilename: exportFilename,
			onCompletion: { result in
				switch result {
				case .success:
					Logger.services.info("File export succeeded for \(exportFilename, privacy: .public)")
					isExporting = false
				case .failure(let error):
					Logger.services.error("File export failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		)
		.listStyle(.inset)
	}

	private func loadFiles() {
		documentsFiles = []
		applicationSupportFiles = []
		loadApplicationSupportFiles()

		guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
			Logger.data.error("🗂️ nil default document directory path for backup, core data backup failed.")
			return
		}
		if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
			for case let fileURL as URL in enumerator {
				do {
					let fileAttributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
					if fileAttributes.isRegularFile! {
						documentsFiles.append(fileURL)
					}
				} catch {
					Logger.services.error("📁 Load file: \(fileURL, privacy: .public) error: \(error, privacy: .public)")
				}
			}
		}

		documentsFiles.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
		applicationSupportFiles.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
	}

	private func loadApplicationSupportFiles() {
		guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
			return
		}

		if let enumerator = FileManager.default.enumerator(at: appSupport, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
			for case let fileURL as URL in enumerator {
				do {
					let fileAttributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
					if fileAttributes.isRegularFile! {
						applicationSupportFiles.append(fileURL)
					}
				} catch {
					Logger.services.error("📁 Load file: \(fileURL, privacy: .public) error: \(error, privacy: .public)")
				}
			}
		}
	}

	private func isActiveDatabaseFile(_ file: URL) -> Bool {
		guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
			file.deletingLastPathComponent() == appSupport else {
			return false
		}

		let name = file.lastPathComponent
		return name == "Meshtastic.store" || name == "Meshtastic.store-wal" || name == "Meshtastic.store-shm"
	}

	private func fileDisplayName(for file: URL) -> String {
		guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
			return file.lastPathComponent
		}

		let appSupportPath = appSupport.path + "/"
		if file.path.hasPrefix(appSupportPath) {
			return String(file.path.dropFirst(appSupportPath.count))
		}

		return file.lastPathComponent
	}

	@ViewBuilder
	private func databaseSizeRow(title: String, fileName: String) -> some View {
		let file = activeDatabaseFiles.first { $0.lastPathComponent == fileName }
		LabeledContent(title, value: file.map(\.fileSizeString) ?? "Missing")
	}

	@ViewBuilder
	private func fileRow(_ file: URL) -> some View {
		let displayName = fileDisplayName(for: file)
		HStack {
			VStack(alignment: .leading ) {
				if file.pathExtension.contains("sqlite") {
					Label {
						Text("Node Core Data Backup \(displayName) - \(file.creationDate?.formatted(date: .numeric, time: .shortened) ?? "") - \(file.fileSizeString)")
					} icon: {
						Image(systemName: "cylinder.split.1x2")
							.symbolRenderingMode(.hierarchical)
							.font(idiom == .phone ? .callout : .title)
							.frame(width: 35)
					}
				} else {
					Label {
						Text("\(displayName) - \(file.creationDate?.formatted(date: .numeric, time: .shortened) ?? "") - \(file.fileSizeString)")
					} icon: {
						Image(systemName: "doc.text")
							.symbolRenderingMode(.hierarchical)
							.font(idiom == .phone ? .callout : .title)
							.frame(width: 35)
					}
				}
			}
#if targetEnvironment(macCatalyst)
			Spacer()
			HStack(spacing: 12) {
				Button {
					beginExport(for: file)
				} label: {
					Label("", systemImage: "square.and.arrow.down")
				}
				.buttonStyle(.borderless)

				Button {
					deleteFile(file)
				} label: {
					Label("", systemImage: "trash")
				}
				.buttonStyle(.borderless)
			}
#endif
		}
		.swipeActions {
			downloadFileButton(for: file)
			deleteFileButton(for: file)
		}
	}

	@ViewBuilder
	private func downloadFileButton(for file: URL) -> some View {
		Button {
			beginExport(for: file)
		} label: {
			Label("Download", systemImage: "square.and.arrow.down")
		}
		.tint(.accentColor)
	}

	@ViewBuilder
	private func deleteFileButton(for file: URL) -> some View {
		Button(role: .destructive) {
			deleteFile(file)
		} label: {
			Label("Delete", systemImage: "trash")
		}
	}

	private func beginExport(for file: URL) {
		exportDocument = BinaryFileDocument(url: file)
		exportFilename = file.deletingPathExtension().lastPathComponent
		exportContentType = UTType(filenameExtension: file.pathExtension) ?? .data
		isExporting = true
	}

	private func deleteFile(_ file: URL) {
		do {
			try FileManager.default.removeItem(at: file)
			loadFiles()
		} catch {
			Logger.services.error("🗑️ Delete file error: \(error, privacy: .public)")
		}
	}
}

struct BinaryFileDocument: FileDocument {
	static var readableContentTypes: [UTType] { [.data] }

	let data: Data

	init(data: Data) {
		self.data = data
	}

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

#Preview {
	AppData()
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
