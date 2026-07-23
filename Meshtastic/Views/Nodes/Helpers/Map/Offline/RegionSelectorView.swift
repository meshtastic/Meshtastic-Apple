//
//  RegionSelectorView.swift
//  Meshtastic
//
//  A full-map area picker. A selection rectangle sits over the map; the user pans/
//  zooms the map underneath AND can drag the rectangle around (center handle) or
//  reshape it (corner handles) for any aspect ratio. The framed area becomes the
//  download bounds, with a live (network-accurate) size estimate, a style choice
//  (street vs. US topo), a detail level, and the per-map / total download limits.
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

/// Reports the bottom control panel's measured height up to the selector.
private struct PanelHeightKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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

	/// The selection rectangle in the picker's local coordinate space (drag/resize target).
	@State private var selectionRect: CGRect = .zero
	/// Rect snapshot captured at the start of a move/resize gesture.
	@State private var gestureStartRect: CGRect?
	/// Latest visible map region, used as a fallback when `MapProxy.convert` isn't ready yet.
	@State private var currentRegion: MKCoordinateRegion?
	/// Measured height of the bottom control panel, so the selection rect stays above it (all four
	/// corners remain on the map and grabbable).
	@State private var controlPanelHeight: CGFloat = 0

	/// Network-accurate size (exact for street, sampled for topo); nil until computed.
	@State private var estimatedBytes: Int64?
	/// True while the accurate estimate is being (re)computed.
	@State private var isEstimating = false

	private enum Corner: CaseIterable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

	init(target: OfflineRegionTarget, replacing: OfflineMapRegion? = nil) {
		self.target = target
		self.replacing = replacing
		_camera = State(initialValue: .region(target.region))
		_name = State(initialValue: target.name)
	}

	private let minRectSize: CGFloat = 64

	var body: some View {
		GeometryReader { geo in
			MapReader { proxy in
				ZStack(alignment: .bottom) {
					// Pan/zoom only, no rotate/pitch: keeps the map north-up so the move handle's
					// "Move north/south/east/west" VoiceOver actions stay screen-accurate.
					Map(position: $camera, interactionModes: [.pan, .zoom])
						.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
						.onMapCameraChange(frequency: .continuous) { context in
							currentRegion = context.region
							recompute(proxy: proxy, size: geo.size)
						}

					selectionLayer(proxy: proxy, size: geo.size)

					controlPanel
						.background(GeometryReader { panelGeo in
							Color.clear.preference(key: PanelHeightKey.self, value: panelGeo.size.height)
						})
				}
				.onPreferenceChange(PanelHeightKey.self) { controlPanelHeight = $0 }
				.onAppear {
					currentRegion = target.region
					initRect(size: geo.size)
					recompute(proxy: proxy, size: geo.size)
				}
				.onChange(of: geo.size) { _, newSize in
					clampRect(to: newSize)
					recompute(proxy: proxy, size: newSize)
				}
				.onChange(of: controlPanelHeight) {
					clampRect(to: geo.size)
					recompute(proxy: proxy, size: geo.size)
				}
			}
		}
		.navigationTitle("Choose Area")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: estimateKey) { await runEstimate() }
	}

	// MARK: - Selection rectangle (dim + border + drag/resize handles)

	@ViewBuilder
	private func selectionLayer(proxy: MapProxy, size: CGSize) -> some View {
		if selectionRect.width > 1, selectionRect.height > 1 {
		ZStack(alignment: .topLeading) {
			// Dim everything outside the selection (non-interactive: the map still pans/zooms through it).
			Path { path in
				path.addRect(CGRect(origin: .zero, size: size))
				path.addRoundedRect(in: selectionRect, cornerSize: CGSize(width: 14, height: 14))
			}
			.fill(Color.black.opacity(0.28), style: FillStyle(eoFill: true))
			.allowsHitTesting(false)

			RoundedRectangle(cornerRadius: 14)
				.stroke(.white, lineWidth: 3)
				.frame(width: selectionRect.width, height: selectionRect.height)
				.position(x: selectionRect.midX, y: selectionRect.midY)
				.shadow(radius: 3)
				.allowsHitTesting(false)

			// Move handle (center) — drag to reposition the rectangle.
			Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
				.font(.system(size: 15, weight: .bold))
				.foregroundStyle(Color.accentColor)
				.frame(width: 40, height: 40)
				.background(Circle().fill(.white).shadow(radius: 2))
				.position(x: selectionRect.midX, y: selectionRect.midY)
				.gesture(moveGesture(proxy: proxy, size: size))
				.accessibilityElement()
				.accessibilityLabel(String(localized: "Move selection", comment: "VoiceOver label for the region rectangle's move handle"))
				.accessibilityHint(String(localized: "Repositions the selected download area on the map", comment: "VoiceOver hint for the region rectangle's move handle"))
				.accessibilityAddTraits(.isButton)
				.accessibilityAction(named: String(localized: "Move north", comment: "VoiceOver custom action: nudge the region area up")) { nudgeMove(dx: 0, dy: -1, proxy: proxy, size: size) }
				.accessibilityAction(named: String(localized: "Move south", comment: "VoiceOver custom action: nudge the region area down")) { nudgeMove(dx: 0, dy: 1, proxy: proxy, size: size) }
				.accessibilityAction(named: String(localized: "Move east", comment: "VoiceOver custom action: nudge the region area right")) { nudgeMove(dx: 1, dy: 0, proxy: proxy, size: size) }
				.accessibilityAction(named: String(localized: "Move west", comment: "VoiceOver custom action: nudge the region area left")) { nudgeMove(dx: -1, dy: 0, proxy: proxy, size: size) }

			// Corner handles — drag to reshape.
			ForEach(Corner.allCases, id: \.self) { corner in
				Circle()
					.fill(.white)
					.frame(width: 24, height: 24)
					.overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
					.shadow(radius: 2)
					.position(handlePosition(corner))
					.gesture(resizeGesture(corner, proxy: proxy, size: size))
					.accessibilityElement()
					.accessibilityLabel(cornerLabel(corner))
					.accessibilityHint(String(localized: "Adjustable. Swipe up to expand, swipe down to shrink the selected area from this corner", comment: "VoiceOver hint for a region rectangle corner handle"))
					.accessibilityAdjustableAction { direction in
						nudgeCorner(corner, direction: direction, proxy: proxy, size: size)
					}
			}
		}
		.frame(width: size.width, height: size.height, alignment: .topLeading)
		}
	}

	private func handlePosition(_ corner: Corner) -> CGPoint {
		switch corner {
		case .topLeading: return CGPoint(x: selectionRect.minX, y: selectionRect.minY)
		case .topTrailing: return CGPoint(x: selectionRect.maxX, y: selectionRect.minY)
		case .bottomLeading: return CGPoint(x: selectionRect.minX, y: selectionRect.maxY)
		case .bottomTrailing: return CGPoint(x: selectionRect.maxX, y: selectionRect.maxY)
		}
	}

	private func cornerLabel(_ corner: Corner) -> String {
		switch corner {
		case .topLeading: return String(localized: "Top leading corner handle", comment: "VoiceOver label for the region rectangle's top leading resize handle")
		case .topTrailing: return String(localized: "Top trailing corner handle", comment: "VoiceOver label for the region rectangle's top trailing resize handle")
		case .bottomLeading: return String(localized: "Bottom leading corner handle", comment: "VoiceOver label for the region rectangle's bottom leading resize handle")
		case .bottomTrailing: return String(localized: "Bottom trailing corner handle", comment: "VoiceOver label for the region rectangle's bottom trailing resize handle")
		}
	}

	/// VoiceOver equivalent of `moveGesture`: nudges the whole rect a fixed step in one
	/// screen-space direction, then clamps and recomputes bounds exactly like a drag does.
	private func nudgeMove(dx: CGFloat, dy: CGFloat, proxy: MapProxy, size: CGSize) {
		let step: CGFloat = 20
		var rect = selectionRect
		rect.origin.x += dx * step
		rect.origin.y += dy * step
		selectionRect = clampedMove(rect, in: size)
		recompute(proxy: proxy, size: size)
	}

	/// VoiceOver equivalent of `resizeGesture`: increment grows the rect from `corner` by a
	/// fixed step (moving the corner away from the rect's center), decrement shrinks it back
	/// toward center, using the same per-corner min/max math the drag gesture uses.
	private func nudgeCorner(_ corner: Corner, direction: AccessibilityAdjustmentDirection, proxy: MapProxy, size: CGSize) {
		let step: CGFloat = direction == .increment ? 20 : -20
		var minX = selectionRect.minX, minY = selectionRect.minY, maxX = selectionRect.maxX, maxY = selectionRect.maxY
		switch corner {
		case .topLeading: minX -= step; minY -= step
		case .topTrailing: maxX += step; minY -= step
		case .bottomLeading: minX -= step; maxY += step
		case .bottomTrailing: maxX += step; maxY += step
		}
		selectionRect = normalizedClamped(minX, minY, maxX, maxY, in: size)
		recompute(proxy: proxy, size: size)
	}

	private func moveGesture(proxy: MapProxy, size: CGSize) -> some Gesture {
		DragGesture()
			.onChanged { value in
				let start = gestureStartRect ?? selectionRect
				if gestureStartRect == nil { gestureStartRect = start }
				var rect = start
				rect.origin.x += value.translation.width
				rect.origin.y += value.translation.height
				selectionRect = clampedMove(rect, in: size)
				recompute(proxy: proxy, size: size)
			}
			.onEnded { _ in gestureStartRect = nil; recompute(proxy: proxy, size: size) }
	}

	private func resizeGesture(_ corner: Corner, proxy: MapProxy, size: CGSize) -> some Gesture {
		DragGesture()
			.onChanged { value in
				let start = gestureStartRect ?? selectionRect
				if gestureStartRect == nil { gestureStartRect = start }
				var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
				switch corner {
				case .topLeading: minX += value.translation.width; minY += value.translation.height
				case .topTrailing: maxX += value.translation.width; minY += value.translation.height
				case .bottomLeading: minX += value.translation.width; maxY += value.translation.height
				case .bottomTrailing: maxX += value.translation.width; maxY += value.translation.height
				}
				selectionRect = normalizedClamped(minX, minY, maxX, maxY, in: size)
				recompute(proxy: proxy, size: size)
			}
			.onEnded { _ in gestureStartRect = nil; recompute(proxy: proxy, size: size) }
	}

	// MARK: - Rect geometry

	/// The on-map area the selection rectangle must stay inside: full width/height minus screen-edge
	/// margins and the bottom control panel, so every corner handle stays on the map and grabbable.
	private func usableRect(in size: CGSize) -> CGRect {
		let top: CGFloat = 16
		let side: CGFloat = 14
		let panel = controlPanelHeight > 0 ? controlPanelHeight : 300
		let bottomInset = panel + 24   // gap above the panel + room for the corner handles
		let minX = side
		let maxX = max(minX + minRectSize, size.width - side)
		let minY = top
		let maxY = max(minY + minRectSize, size.height - bottomInset)
		return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
	}

	private func initRect(size: CGSize) {
		guard selectionRect == .zero, size.width > 0, size.height > 0 else { return }
		let area = usableRect(in: size)
		selectionRect = (area.width > 120 && area.height > 120) ? area.insetBy(dx: 20, dy: 20) : area
	}

	private func clampRect(to size: CGSize) {
		guard size.width > 0, size.height > 0 else { return }
		if selectionRect == .zero { initRect(size: size); return }
		selectionRect = normalizedClamped(selectionRect.minX, selectionRect.minY, selectionRect.maxX, selectionRect.maxY, in: size)
	}

	private func clampedMove(_ rect: CGRect, in size: CGSize) -> CGRect {
		let area = usableRect(in: size)
		var rect = rect
		rect.size.width = min(rect.width, area.width)
		rect.size.height = min(rect.height, area.height)
		rect.origin.x = min(max(area.minX, rect.origin.x), area.maxX - rect.width)
		rect.origin.y = min(max(area.minY, rect.origin.y), area.maxY - rect.height)
		return rect
	}

	private func normalizedClamped(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, in size: CGSize) -> CGRect {
		let area = usableRect(in: size)
		var left = max(area.minX, min(x0, x1))
		var right = min(area.maxX, max(x0, x1))
		var topY = max(area.minY, min(y0, y1))
		var bottomY = min(area.maxY, max(y0, y1))
		if right - left < minRectSize { right = min(area.maxX, left + minRectSize); left = max(area.minX, right - minRectSize) }
		if bottomY - topY < minRectSize { bottomY = min(area.maxY, topY + minRectSize); topY = max(area.minY, bottomY - minRectSize) }
		return CGRect(x: left, y: topY, width: right - left, height: bottomY - topY)
	}

	/// Converts the selection rectangle into geographic bounds. Prefers `MapProxy.convert`; falls back
	/// to projecting the rect onto the current region when the proxy isn't ready (fixes the initial
	/// "Download disabled until you jiggle the map" case).
	private func recompute(proxy: MapProxy, size: CGSize) {
		let rect = selectionRect
		guard rect.width > 4, rect.height > 4 else { return }
		if let northWest = proxy.convert(CGPoint(x: rect.minX, y: rect.minY), from: .local),
		   let southEast = proxy.convert(CGPoint(x: rect.maxX, y: rect.maxY), from: .local) {
			bounds = GeoBounds(
				minLon: min(northWest.longitude, southEast.longitude),
				minLat: min(northWest.latitude, southEast.latitude),
				maxLon: max(northWest.longitude, southEast.longitude),
				maxLat: max(northWest.latitude, southEast.latitude)
			)
		} else if let region = currentRegion {
			bounds = boundsFromRegion(region, rect: rect, size: size)
		}
	}

	/// Approximate bounds for `rect` within a map showing `region` across `size` (fallback only).
	private func boundsFromRegion(_ region: MKCoordinateRegion, rect: CGRect, size: CGSize) -> GeoBounds? {
		guard size.width > 0, size.height > 0 else { return nil }
		let leftLon = region.center.longitude - region.span.longitudeDelta / 2
		let topLat = region.center.latitude + region.span.latitudeDelta / 2
		let lonPerPx = region.span.longitudeDelta / size.width
		let latPerPx = region.span.latitudeDelta / size.height
		return GeoBounds(
			minLon: leftLon + rect.minX * lonPerPx,
			minLat: topLat - rect.maxY * latPerPx,
			maxLon: leftLon + rect.maxX * lonPerPx,
			maxLat: topLat - rect.minY * latPerPx
		)
	}

	// MARK: - Controls

	private var controlPanel: some View {
		VStack(spacing: 12) {
			Text("Drag the box, its corners, or the map to frame an area")
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			Picker("Detail", selection: $detail) {
				ForEach(OfflineMapDetailLevel.allCases) { level in
					Text(level.label).tag(level)
				}
			}
			.pickerStyle(.segmented)

			Text("Size of selected map: \(sizeText)")
				.font(.subheadline)

			if let warning {
				Label(warning, systemImage: "exclamationmark.triangle.fill")
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
				.disabled(!canDownload)
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

	/// The single most relevant warning to show (overlap → limit), or nil.
	private var warning: String? {
		if let overlap {
			return String(localized: "Overlaps \u{201C}\(overlap.name)\u{201D}. Move or resize so it doesn\u{2019}t overlap an existing map.")
		}
		if let bytes = displayedBytes {
			return manager.downloadBlockReason(estimatedBytes: bytes, replacing: replacing)
		}
		return nil
	}

	private var canDownload: Bool {
		bounds != nil && !manager.isDownloading && overlap == nil && warning == nil
	}

	// MARK: - Size estimate

	/// Synchronous, network-free rough estimate (shown immediately while framing).
	private var roughBytes: Int64? {
		guard let bounds else { return nil }
		return PMTilesExtractor.roughByteEstimate(in: bounds, minZoom: detail.minZoom, maxZoom: detail.maxZoom)
	}

	/// Best available estimate (network-accurate once computed, else rough).
	private var displayedBytes: Int64? { estimatedBytes ?? roughBytes }

	private var sizeText: String {
		guard let bytes = displayedBytes else { return "—" }
		let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
		return isEstimating ? "\u{2248} \(formatted)" : formatted
	}

	/// Re-runs whenever the framed area / detail settle (debounced via `.task(id:)`).
	private var estimateKey: String {
		guard let bounds else { return "none" }
		func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
		return "\(detail.rawValue)|\(round4(bounds.minLon)),\(round4(bounds.minLat)),\(round4(bounds.maxLon)),\(round4(bounds.maxLat))"
	}

	private func runEstimate() async {
		estimatedBytes = nil
		guard let bounds else { isEstimating = false; return }
		isEstimating = true
		// Debounce: cancelled (and restarted) by `.task(id:)` if the area keeps changing.
		do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
		if Task.isCancelled { return }
		let bytes = await Self.computeEstimate(bounds: bounds, detail: detail)
		if Task.isCancelled { return }
		estimatedBytes = bytes
		isEstimating = false
	}

	/// Network-accurate size (the exact plan the download uses), falling back to the rough estimate.
	private static func computeEstimate(bounds: GeoBounds, detail: OfflineMapDetailLevel) async -> Int64 {
		if let result = try? await PMTilesExtractor().estimate(bounds: bounds, minZoom: detail.minZoom, maxZoom: detail.maxZoom) {
			return result.bytes
		}
		return PMTilesExtractor.roughByteEstimate(in: bounds, minZoom: detail.minZoom, maxZoom: detail.maxZoom)
	}

	private func startDownload() {
		guard let bounds else { return }
		manager.startDownload(name: name, bounds: bounds, detail: detail, replacing: replacing)
		dismiss()
	}
}
