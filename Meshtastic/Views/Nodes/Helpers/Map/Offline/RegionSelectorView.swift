//
//  RegionSelectorView.swift
//  Meshtastic
//
//  A full-map area picker: a fixed selection frame sits over the map while the
//  user pans/zooms underneath. The framed area becomes the download bounds, with
//  a live size estimate and a detail-level choice.
//

import SwiftUI
import MapKit

/// A place to seed the selector with (city, POI, or current location).
struct OfflineRegionTarget: Identifiable, Hashable {
	let id = UUID()
	var name: String
	var centerLatitude: Double
	var centerLongitude: Double
	var latitudeDelta: Double
	var longitudeDelta: Double

	init(name: String, region: MKCoordinateRegion) {
		self.name = name
		self.centerLatitude = region.center.latitude
		self.centerLongitude = region.center.longitude
		self.latitudeDelta = region.span.latitudeDelta
		self.longitudeDelta = region.span.longitudeDelta
	}

	var region: MKCoordinateRegion {
		MKCoordinateRegion(
			center: CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude),
			span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
		)
	}
}

struct RegionSelectorView: View {
	let target: OfflineRegionTarget
	/// When resizing, the existing region this download replaces on success.
	let replacing: OfflineMapRegion?

	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var manager = OfflineMapManager.shared
	@State private var camera: MapCameraPosition
	@State private var bounds: GeoBounds?
	@State private var detail: OfflineMapDetailLevel = .standard
	@State private var name: String

	init(target: OfflineRegionTarget, replacing: OfflineMapRegion? = nil) {
		self.target = target
		self.replacing = replacing
		_camera = State(initialValue: .region(target.region))
		_name = State(initialValue: target.name)
	}

	private let horizontalInset: CGFloat = 28
	private let topInset: CGFloat = 70
	private let bottomInset: CGFloat = 240

	var body: some View {
		GeometryReader { geo in
			MapReader { proxy in
				ZStack(alignment: .bottom) {
					Map(position: $camera)
						.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
						.onMapCameraChange(frequency: .continuous) { _ in
							recompute(proxy: proxy, size: geo.size)
						}

					selectionFrame(size: geo.size)
						.allowsHitTesting(false)

					controlPanel
				}
				.onAppear { recompute(proxy: proxy, size: geo.size) }
			}
		}
		.ignoresSafeArea(edges: .top)
		.navigationTitle("Choose Area")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Selection frame

	private func selectionRect(in size: CGSize) -> CGRect {
		CGRect(
			x: horizontalInset,
			y: topInset,
			width: max(size.width - horizontalInset * 2, 0),
			height: max(size.height - topInset - bottomInset, 0)
		)
	}

	private func selectionFrame(size: CGSize) -> some View {
		let rect = selectionRect(in: size)
		return RoundedRectangle(cornerRadius: 14)
			.path(in: rect)
			.stroke(.white, lineWidth: 3)
			.shadow(radius: 3)
	}

	private func recompute(proxy: MapProxy, size: CGSize) {
		let rect = selectionRect(in: size)
		guard rect.width > 0, rect.height > 0,
			  let northWest = proxy.convert(CGPoint(x: rect.minX, y: rect.minY), from: .local),
			  let southEast = proxy.convert(CGPoint(x: rect.maxX, y: rect.maxY), from: .local) else {
			return
		}
		bounds = GeoBounds(
			minLon: min(northWest.longitude, southEast.longitude),
			minLat: min(northWest.latitude, southEast.latitude),
			maxLon: max(northWest.longitude, southEast.longitude),
			maxLat: max(northWest.latitude, southEast.latitude)
		)
	}

	// MARK: - Controls

	private var controlPanel: some View {
		VStack(spacing: 12) {
			Text("Pan and zoom to frame the area")
				.font(.caption)
				.foregroundStyle(.secondary)

			Picker("Detail", selection: $detail) {
				ForEach(OfflineMapDetailLevel.allCases) { level in
					Text(level.label).tag(level)
				}
			}
			.pickerStyle(.segmented)

			Text("Size of selected map: \(estimatedSize)")
				.font(.subheadline)

			if let overlap {
				Label("Overlaps \u{201C}\(overlap.name)\u{201D}. Move or zoom so it doesn\u{2019}t overlap an existing map.", systemImage: "exclamationmark.triangle.fill")
					.font(.caption)
					.foregroundStyle(.orange)
					.multilineTextAlignment(.center)
			}

			HStack(spacing: 12) {
				Button(role: .cancel) { dismiss() } label: {
					Text("Cancel").frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)

				Button {
					startDownload()
				} label: {
					Text("Download").frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.disabled(bounds == nil || manager.isDownloading || overlap != nil)
			}
		}
		.padding()
		.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
		.padding(.horizontal, 12)
		.padding(.bottom, 8)
	}

	/// An existing region the framed area overlaps (downloads must not overlap), or nil.
	private var overlap: OfflineMapRegion? {
		bounds.flatMap { manager.overlappingRegion(with: $0, excluding: replacing) }
	}

	private var estimatedSize: String {
		guard let bounds else { return "—" }
		let bytes = PMTilesExtractor.roughByteEstimate(in: bounds, minZoom: detail.minZoom, maxZoom: detail.maxZoom)
		return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
	}

	private func startDownload() {
		guard let bounds else { return }
		manager.startDownload(name: name, bounds: bounds, detail: detail, replacing: replacing)
		dismiss()
	}
}
