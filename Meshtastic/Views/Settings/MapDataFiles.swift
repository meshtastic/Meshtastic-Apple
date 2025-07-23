import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct MapDataFiles: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@ObservedObject private var mapDataManager = MapDataManager.shared

	@State private var isShowingFilePicker = false
	@State private var isProcessing = false
	@State private var processingProgress: Double = 0.0
	@State private var showError = false
	@State private var errorMessage = ""
	@State private var showSuccess = false
	@State private var successMessage = ""

	var body: some View {
		VStack(spacing: 20) {
			// Header
			VStack(alignment: .leading, spacing: 8) {
								Text(NSLocalizedString("Upload Map Data", comment: "Title for map data upload screen"))
					.font(.title2)
					.fontWeight(.bold)

				Text("Upload GeoJSON files to display custom map overlays. Files are stored locally and can be up to 10MB.")
					.font(.caption)
					.foregroundColor(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal)

			// Upload Button
			Button(action: {
				isShowingFilePicker = true
			}) {
				HStack {
					Image(systemName: "doc.badge.plus")
						.font(.title2)
					Text(NSLocalizedString("Select Map Data File", comment: "Button text for selecting map data file"))
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

			// Current Files Section
			VStack(alignment: .leading, spacing: 12) {
				Text(NSLocalizedString("Uploaded Files", comment: "Section header for uploaded files"))
					.font(.headline)
					.padding(.horizontal)

				let uploadedFiles = mapDataManager.getUploadedFiles()

				if uploadedFiles.isEmpty {
					VStack(spacing: 8) {
						Image(systemName: "doc.text")
							.font(.title)
							.foregroundColor(.secondary)
						Text(NSLocalizedString("No files uploaded yet", comment: "Empty state text when no files are uploaded"))
							.font(.caption)
							.foregroundColor(.secondary)
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 40)
				} else {
					ScrollView {
						LazyVStack(spacing: 8) {
							ForEach(uploadedFiles) { file in
								MapDataFileRow(file: file) {
									deleteFile(file)
								}
							}
						}
						.padding(.horizontal)
					}
				}
			}

			Spacer()
		}
		.navigationTitle("Map Data")
		.navigationBarTitleDisplayMode(.inline)
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
			Button("OK") { }
		} message: {
			Text(errorMessage)
		}
		.alert("Upload Success", isPresented: $showSuccess) {
			Button("OK") { }
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

						successMessage = "Successfully uploaded '\(metadata.originalName)' with \(metadata.overlayCount) overlays"
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
			errorMessage = "Failed to access file: \(error.localizedDescription)"
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
					errorMessage = "Failed to delete file: \(error.localizedDescription)"
					showError = true
				}
			}
		}
	}
}

// MARK: - Supporting Views

struct MapDataFileRow: View {
	let file: MapDataMetadata
	let onDelete: () -> Void

	var body: some View {
		HStack {
			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text(file.originalName)
						.font(.headline)
						.lineLimit(1)

					Spacer()
				}

				HStack {
					Text(file.format.uppercased())
						.font(.caption)
						.padding(.horizontal, 8)
						.padding(.vertical, 2)
						.background(Color.secondary.opacity(0.2))
						.cornerRadius(4)

					Text(file.fileSizeString)
						.font(.caption)
						.foregroundColor(.secondary)

					Text("•")
						.font(.caption)
						.foregroundColor(.secondary)

					Text("\(file.overlayCount) overlays")
						.font(.caption)
						.foregroundColor(.secondary)

					Spacer()

					Text(file.uploadDateString)
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}

			Button(action: onDelete) {
				Image(systemName: "trash")
					.foregroundColor(.red)
			}
			.buttonStyle(BorderlessButtonStyle())
		}
		.padding()
		.background(Color(.systemBackground))
		.cornerRadius(8)
		.shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
	}
}

#Preview {
	NavigationView {
		MapDataFiles()
	}
}
