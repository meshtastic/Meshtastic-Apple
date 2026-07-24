//
//  MapSettingsForm.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 10/3/23.
//

import SwiftUI
import MapKit
import OSLog
import UniformTypeIdentifiers

struct MapSettingsForm: View {
	@Environment(\.dismiss) private var dismiss
	@State private var currentDetent = PresentationDetent.medium
	@State private var isShowingFilePicker = false
	@State private var isProcessingUpload = false
	@State private var showUploadError = false
	@State private var uploadErrorMessage = ""
	@AppStorage("meshMapShowNodeHistory") private var nodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var enableMapRouteLines = false
	@AppStorage("enableMapConvexHull") private var convexHull = false
	@AppStorage("enableMapWaypoints") private var enableMapWaypoints = true
	@AppStorage("enableMapUserLocation") private var enableMapUserLocation = true
	@AppStorage("mapOverlaysEnabled") private var mapOverlaysEnabled = false
	@AppStorage("enableOfflineTiles") private var enableOfflineTiles = false
	@AppStorage("enableMapClustering") private var enableMapClustering = true
	@AppStorage("enableMapPreciseLocationsOnly") private var preciseLocationsOnly = false
	@ObservedObject private var mapDataManager = MapDataManager.shared
	@ObservedObject private var offlineMapManager = OfflineMapManager.shared
	@Binding var traffic: Bool
	@Binding var pointsOfInterest: Bool
	@Binding var mapLayer: MapLayer
	@Binding var meshMap: Bool
	@Binding var enabledOverlayConfigs: Set<UUID>

	var body: some View {

		NavigationStack {
			Form {
				Section(header: Text("Map Options")) {
					Picker(selection: $mapLayer, label: Text("")) {
						ForEach(MapLayer.allCases, id: \.self) { layer in
							// `.offline` is an overlay toggle now, not a base layer — keep it out of the base picker.
							if layer != MapLayer.offline {
								Text(layer.localized.capitalized)
							}
						}
					}
					.pickerStyle(SegmentedPickerStyle())
					.padding(.top, 5)
					.padding(.bottom, 5)
					.onChange(of: mapLayer) { _, newMapLayer in
						UserDefaults.mapLayer = newMapLayer
					}
					if meshMap {
						Toggle(isOn: $enableMapWaypoints) {
							Label {
								Text("Waypoints")
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.multicolor)
							}
						}
						.tint(.accentColor)
						Toggle(isOn: $preciseLocationsOnly) {
							Label {
								VStack(alignment: .leading) {
									Text("Precise Locations Only")
									Text("Hides nodes that broadcast an approximate location (the ones drawn with a translucent precision circle).")
										.font(.caption)
										.foregroundColor(.secondary)
								}
							} icon: {
								Image(systemName: "scope")
							}
						}
						.tint(.accentColor)
						Toggle(isOn: $enableMapClustering) {
							Label {
								VStack(alignment: .leading) {
									Text("Cluster Nodes")
									Text("Groups nearby nodes into one numbered pin; tap it to zoom in. Turn off to always show every node.")
										.font(.caption)
										.foregroundColor(.secondary)
								}
							} icon: {
								Image(systemName: "circle.grid.3x3.fill")
							}
						}
						.tint(.accentColor)
						Toggle(isOn: $enableMapUserLocation) {
							Label {
								Text("My Location")
							} icon: {
								Image(systemName: "location.fill")
									.symbolRenderingMode(.multicolor)
							}
						}
						.tint(.accentColor)
					}
					if !meshMap {
						Toggle(isOn: $nodeHistory) {
							Label("Node History", systemImage: "building.columns.fill")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						Toggle(isOn: $enableMapRouteLines) {
							Label("Route Lines", systemImage: "road.lanes")
						}
						.tint(.accentColor)

					}
					Toggle(isOn: $convexHull) {
						Label("Convex Hull", systemImage: "button.angledbottom.horizontal.right")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onTapGesture {
						self.convexHull.toggle()
						UserDefaults.enableMapConvexHull = self.convexHull
					}
					Toggle(isOn: $traffic) {
						Label("Traffic", systemImage: "car")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onTapGesture {
						self.traffic.toggle()
						UserDefaults.enableMapTraffic = self.traffic
					}
					Toggle(isOn: $pointsOfInterest) {
						Label {
							Text("Points of Interest")
						} icon: {
							Image(systemName: "mappin.and.ellipse")
								.symbolRenderingMode(.multicolor)
						}
					}
					.tint(.accentColor)
					.onTapGesture {
						self.pointsOfInterest.toggle()
						UserDefaults.enableMapPointsOfInterest = self.pointsOfInterest
					}
				}

				if meshMap {
					Section(header: Text("Offline Maps")) {
						NavigationLink {
							OfflineMapsList()
						} label: {
							Label {
								VStack(alignment: .leading) {
									Text("Offline Maps")
									if offlineMapManager.regions.isEmpty {
										Text("Download map areas to use without a connection.")
											.font(.caption)
											.foregroundColor(.secondary)
									} else {
										Text("\(offlineMapManager.regions.count) downloaded · \(offlineMapManager.formattedTotalSize)")
											.font(.caption)
											.foregroundColor(.secondary)
									}
								}
							} icon: {
								Image(systemName: "arrow.down.circle")
							}
						}
						Toggle(isOn: $enableOfflineTiles) {
							Label {
								VStack(alignment: .leading) {
									Text("Offline Tiles")
									Text("Shows a saved offline map over the covered area, so it still works without an internet connection.")
										.font(.caption)
										.foregroundColor(.secondary)
								}
							} icon: {
								Image(systemName: "square.dashed")
							}
						}
						.tint(.accentColor)
					}
				}

				Section(header: Text("Map Overlays")) {
					let hasUserData = GeoJSONOverlayManager.shared.hasUserData()
					// Master toggle for map overlays
					Toggle(isOn: $mapOverlaysEnabled) {
						Label {
							VStack(alignment: .leading) {
								Text("Map Overlays")
								Text(GeoJSONOverlayManager.shared.getActiveDataSource())
									.font(.caption)
									.foregroundColor(.secondary)
							}
						} icon: {
							Image(systemName: "map")
								.symbolRenderingMode(.multicolor)
						}
					}
					.tint(.accentColor)
					.disabled(!hasUserData && !mapOverlaysEnabled)

					// Show individual file rows when overlays are enabled
					if mapOverlaysEnabled {
						let uploadedFiles = mapDataManager.getUploadedFiles()
						if !uploadedFiles.isEmpty {
							ForEach(uploadedFiles) { file in
								Toggle(isOn: Binding(
									get: {
										return enabledOverlayConfigs.contains(file.id)
									},
									set: { newValue in
										if newValue {
											enabledOverlayConfigs.insert(file.id)
										} else {
											enabledOverlayConfigs.remove(file.id)
										}
									}
								)) {
									Label {
										VStack(alignment: .leading, spacing: 2) {
											Text(file.originalName)
												.font(.subheadline)
												.lineLimit(1)
											// The format pill must never wrap internally (`.fixedSize()` pins it to
											// its natural single-line width) — at large Dynamic Type sizes there's
											// not always room for it plus the feature count on one line, so
											// `ViewThatFits` drops the count to its own line instead.
											ViewThatFits(in: .horizontal) {
												HStack(spacing: 6) {
													overlayFormatPill(file.format)
													Text("\(file.overlayCount) features")
														.font(.caption2)
														.foregroundColor(.secondary)
													Spacer()
													Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
														.font(.caption2)
														.foregroundColor(.secondary)
												}
												VStack(alignment: .leading, spacing: 2) {
													HStack(spacing: 6) {
														overlayFormatPill(file.format)
														Spacer()
														Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
															.font(.caption2)
															.foregroundColor(.secondary)
													}
													Text("\(file.overlayCount) features")
														.font(.caption2)
														.foregroundColor(.secondary)
												}
											}
											Text(file.uploadDate.formatted(date: .abbreviated, time: .shortened))
												.font(.caption2)
												.foregroundColor(.secondary)
										}
									} icon: {
										let isEnabled = enabledOverlayConfigs.contains(file.id)
										Image(systemName: isEnabled ? "doc.fill" : "doc")
											.foregroundColor(isEnabled ? .accentColor : .secondary)
									}
								}
								.tint(.accentColor)
								.swipeActions(edge: .trailing) {
									Button(role: .destructive) {
										deleteOverlayFile(file)
									} label: {
										Label("Delete", systemImage: "trash")
									}
								}
							}
						} else {
							ContentUnavailableView("No map data files uploaded", systemImage: "exclamationmark.triangle")
						}
					}

					// Upload, inline — replaces the former "Manage map data" / "Upload map data
					// to enable overlays" links out to a separate screen.
					Button {
						isShowingFilePicker = true
					} label: {
						Label("Upload Map Data", systemImage: "doc.badge.plus")
					}
					.disabled(isProcessingUpload)

					if isProcessingUpload {
						HStack(spacing: 8) {
							ProgressView()
							Text("Processing file...")
								.font(.caption)
								.foregroundColor(.secondary)
						}
					}
				}
			}
			.navigationTitle("Map Options")
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
			.alert("Upload Error", isPresented: $showUploadError) {
				Button("Ok") { }
			} message: {
				Text(uploadErrorMessage)
			}
		}
		#if targetEnvironment(macCatalyst)
		.overlay(alignment: .topLeading) {
			Button {
				dismiss()
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.system(size: 34))
					.symbolRenderingMode(.palette)
					.foregroundStyle(.white, Color(.systemGray3))
			}
			.accessibilityLabel(String(localized: "Close", comment: "VoiceOver: dismiss this sheet"))
			.buttonStyle(.plain)
			.padding(.top, 12)
			.padding(.leading, 14)
		}
		#endif
		.presentationDetents([.large], selection: $currentDetent)
		.presentationContentInteraction(.scrolls)
		#if !targetEnvironment(macCatalyst)
		.presentationDragIndicator(.visible)
		#endif
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
		.onAppear {
			// Initialize map data manager
			mapDataManager.initialize()
			offlineMapManager.loadIfNeeded()
			// Migrate the legacy `.offline` base layer to the new independent offline-tiles overlay here
			// (a shared entry point), so any presenter — incl. the per-node map — never shows the base
			// picker with an unselectable `.offline` value when its segment is hidden on the new map.
			if mapLayer == .offline {
				mapLayer = .standard
				enableOfflineTiles = true
			}
		}

	}

	// MARK: - Overlay file upload / delete

	private func overlayFormatPill(_ format: String) -> some View {
		Text(format.uppercased())
			.font(.caption2)
			.lineLimit(1)
			.fixedSize()
			.padding(.horizontal, 6)
			.padding(.vertical, 1)
			.background(Color.secondary.opacity(0.2))
			.cornerRadius(4)
	}

	private func handleFileSelection(_ result: Result<[URL], Error>) {
		do {
			guard let selectedFile = try result.get().first else { return }

			isProcessingUpload = true

			Task {
				do {
					_ = try await mapDataManager.processUploadedFile(from: selectedFile)
					await MainActor.run {
						isProcessingUpload = false
						mapOverlaysEnabled = true
					}
				} catch {
					await MainActor.run {
						isProcessingUpload = false
						uploadErrorMessage = error.localizedDescription
						showUploadError = true
					}
				}
			}
		} catch {
			uploadErrorMessage = String.localizedStringWithFormat("Failed to access file: %@".localized, error.localizedDescription)
			showUploadError = true
		}
	}

	private func deleteOverlayFile(_ file: MapDataMetadata) {
		Task {
			do {
				try await mapDataManager.deleteFile(file)
				await MainActor.run {
					enabledOverlayConfigs.remove(file.id)
				}
			} catch {
				await MainActor.run {
					uploadErrorMessage = String.localizedStringWithFormat("Failed to delete file: %@".localized, error.localizedDescription)
					showUploadError = true
				}
			}
		}
	}
}

#Preview {
	MapSettingsForm(
		traffic: .constant(false),
		pointsOfInterest: .constant(true),
		mapLayer: .constant(.standard),
		meshMap: .constant(true),
		enabledOverlayConfigs: .constant(Set<UUID>())
	)
}
