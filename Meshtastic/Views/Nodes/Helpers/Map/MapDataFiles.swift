import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct MapDataFiles: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@ObservedObject private var mapDataManager = MapDataManager.shared
	
	@State private var isShowingFilePicker = false
	@State private var isProcessing = false
	@State private var processingProgress: Double = 0.0
	@State private var showError = false
	@State private var errorMessage = ""
	@State private var showSuccess = false
	@State private var successMessage = ""
	
	var body: some View {
		Form {
			Section(header: Text("Upload Map Overlays")) {
				Text("Upload GeoJSON files to display custom map overlays. Files are stored locally and can be up to 10MB.")
					.font(.callout)
					.foregroundColor(.secondary)
				// Upload Button
				Button(action: {
					isShowingFilePicker = true
				}) {
					HStack {
						Image(systemName: "doc.badge.plus")
							.font(.title2)
						Text("Select Map File")
							.fontWeight(.medium)
					}
					.frame(maxWidth: .infinity)
					.padding()
					.background(Color.accentColor)
					.foregroundColor(.white)
					.cornerRadius(10)
				}
				.disabled(isProcessing)
				.padding(.horizontal)
				
				// Processing Indicator
				if isProcessing {
					VStack(spacing: 12) {
						ProgressView(value: processingProgress)
							.progressViewStyle(LinearProgressViewStyle())
							.padding(.horizontal)
						
						Text("Processing file...")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}
			}
			Section(header: Text("Uploaded Map Overlays")) {
				
				let uploadedFiles = mapDataManager.getUploadedFiles()
				
				if uploadedFiles.isEmpty {
					ContentUnavailableView("No files uploaded", systemImage: "doc.text")
				} else {
					ScrollView {
						LazyVStack() {
							ForEach(Array(uploadedFiles.enumerated()), id: \.offset) { index, file in
								MapDataFileRow(file: file, showDivider: index < uploadedFiles.count - 1) {
									deleteFile(file)
								}
							}
						}
						.padding(.horizontal)
					}
				}
			}
		}
		.fileImporter(
			isPresented: $isShowingFilePicker,
			allowedContentTypes: [
				UTType.json,
				UTType(filenameExtension: "geojson") ?? UTType.json
			],
			allowsMultipleSelection: false
		) { result in
			handleFileSelection(result)
		}
		.alert("Upload Error", isPresented: $showError) {
			Button("Ok") { }
		} message: {
			Text(errorMessage)
		}
		.alert("Upload Success", isPresented: $showSuccess) {
			Button("Ok") { }
		} message: {
			Text(successMessage)
		}
		.onAppear {
			// Initialize map data manager if needed
			mapDataManager.initialize()
		}
	}
	
	// MARK: - File Handling
	
	private func handleFileSelection(_ result: Result<[URL], Error>) {
		do {
			guard let selectedFile = try result.get().first else { return }
			
			// Start processing
			isProcessing = true
			processingProgress = 0.0
			
			// Process file asynchronously
			Task {
				do {
					// Simulate progress
					await simulateProgress()
					
					let metadata = try await mapDataManager.processUploadedFile(from: selectedFile)
					
					await MainActor.run {
						isProcessing = false
						processingProgress = 1.0
						
						successMessage = "Successfully uploaded '\(metadata.originalName)' with \(metadata.overlayCount) overlays".localized
						showSuccess = true
					}
				} catch {
					await MainActor.run {
						isProcessing = false
						processingProgress = 0.0
						
						errorMessage = error.localizedDescription
						showError = true
					}
				}
			}
		} catch {
			errorMessage = "Failed to access file: \(error.localizedDescription)".localized
			showError = true
		}
	}
	
	private func simulateProgress() async {
		for i in 1...10 {
			await MainActor.run {
				processingProgress = Double(i) / 10.0
			}
			try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
		}
	}
	
	private func deleteFile(_ file: MapDataMetadata) {
		Task {
			do {
				try await mapDataManager.deleteFile(file)
			} catch {
				await MainActor.run {
					errorMessage = "Failed to delete file: \(error.localizedDescription)".localized
					showError = true
				}
			}
		}
	}
}

// MARK: - Supporting Views

struct MapDataFileRow: View {
	let file: MapDataMetadata
	let showDivider: Bool
	let onDelete: () -> Void
	
	var body: some View {
		HStack {
			VStack {
				HStack {
					Text(file.originalName)
						.font(.headline)
						.lineLimit(1)
					
					Spacer()
					Text(file.fileSizeString)
						.font(.caption)
						.foregroundColor(.secondary)
					Button(action: onDelete) {
						Image(systemName: "trash")
							.foregroundColor(.red)
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.small)
				}
				HStack {
					Text(file.format.uppercased())
						.font(.caption2)
						.fixedSize()
						.padding(.horizontal, 8)
						.padding(.vertical, 2)
						.background(Color.secondary.opacity(0.2))
						.cornerRadius(4)
					
					Text("\(file.overlayCount) \(file.overlayCount > 1 ? "features".localized : "feature".localized)")
						.font(.caption2)
						.foregroundColor(.secondary)
					Spacer()
					Text(file.uploadDate.formatted())
						.font(.caption2)
						.foregroundColor(.secondary)
				}
			}
		}
		if showDivider {
			Divider()
		}
	}
}

#Preview {
	NavigationView {
		MapDataFiles()
	}
}
