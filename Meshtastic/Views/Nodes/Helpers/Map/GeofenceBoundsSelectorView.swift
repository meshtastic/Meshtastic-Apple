//
//  GeofenceBoundsSelectorView.swift
//  Meshtastic
//
//  Drag-to-define authoring for a waypoint's rectangular geofence (bounding box).
//  A selection rectangle sits over the map; the user pans/zooms the map underneath
//  and drags the rectangle (center handle) or reshapes it (corner handles). The
//  framed area is returned as GeoBounds. Modeled on the offline-map RegionSelectorView.
//

import SwiftUI
import MapKit

struct GeofenceBoundsSelectorView: View {
	/// Where to center the map when there is no existing box (the waypoint's location).
	let center: CLLocationCoordinate2D
	/// Existing bounding box to edit, if any.
	let initialBounds: GeoBounds?
	/// Called with the framed area when the user taps Done.
	var onComplete: (GeoBounds) -> Void

	@Environment(\.dismiss) private var dismiss
	@State private var camera: MapCameraPosition
	@State private var bounds: GeoBounds?

	/// The selection rectangle in the view's local coordinate space (drag/resize target).
	@State private var selectionRect: CGRect = .zero
	/// Rect snapshot captured at the start of a move/resize gesture.
	@State private var gestureStartRect: CGRect?
	/// Latest visible map region; fallback when `MapProxy.convert` isn't ready yet.
	@State private var currentRegion: MKCoordinateRegion?

	private let initialRegion: MKCoordinateRegion
	private let minRectSize: CGFloat = 64
	private enum Corner: CaseIterable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

	init(center: CLLocationCoordinate2D, initialBounds: GeoBounds?, onComplete: @escaping (GeoBounds) -> Void) {
		self.center = center
		self.initialBounds = initialBounds
		self.onComplete = onComplete
		let region: MKCoordinateRegion
		if let b = initialBounds {
			let mid = CLLocationCoordinate2D(latitude: (b.minLat + b.maxLat) / 2, longitude: (b.minLon + b.maxLon) / 2)
			let span = MKCoordinateSpan(
				latitudeDelta: max((b.maxLat - b.minLat) * 2.2, 0.02),
				longitudeDelta: max((b.maxLon - b.minLon) * 2.2, 0.02)
			)
			region = MKCoordinateRegion(center: mid, span: span)
		} else {
			region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
		}
		self.initialRegion = region
		_camera = State(initialValue: .region(region))
	}

	var body: some View {
		NavigationStack {
			GeometryReader { geo in
				MapReader { proxy in
					ZStack(alignment: .bottom) {
						Map(position: $camera)
							.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
							.onMapCameraChange(frequency: .continuous) { context in
								currentRegion = context.region
								recompute(proxy: proxy, size: geo.size)
							}

						selectionLayer(proxy: proxy, size: geo.size)

						instructionPanel
					}
					.onAppear {
						currentRegion = initialRegion
						initRect(proxy: proxy, size: geo.size)
						recompute(proxy: proxy, size: geo.size)
					}
					.onChange(of: geo.size) { _, newSize in
						clampRect(proxy: proxy, to: newSize)
						recompute(proxy: proxy, size: newSize)
					}
				}
			}
			.navigationTitle("Geofence Area")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						if let bounds { onComplete(bounds) }
						dismiss()
					}
					.disabled(bounds == nil)
				}
			}
		}
	}

	// MARK: - Selection rectangle (dim + border + drag/resize handles)

	@ViewBuilder
	private func selectionLayer(proxy: MapProxy, size: CGSize) -> some View {
		if selectionRect.width > 1, selectionRect.height > 1 {
			ZStack(alignment: .topLeading) {
				// Dim outside the selection (non-interactive so the map still pans/zooms through it).
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

				// Move handle (center).
				Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
					.font(.system(size: 15, weight: .bold))
					.foregroundStyle(Color.accentColor)
					.frame(width: 40, height: 40)
					.background(Circle().fill(.white).shadow(radius: 2))
					.position(x: selectionRect.midX, y: selectionRect.midY)
					.gesture(moveGesture(proxy: proxy, size: size))

				// Corner handles.
				ForEach(Corner.allCases, id: \.self) { corner in
					Circle()
						.fill(.white)
						.frame(width: 24, height: 24)
						.overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
						.shadow(radius: 2)
						.position(handlePosition(corner))
						.gesture(resizeGesture(corner, proxy: proxy, size: size))
				}
			}
			.frame(width: size.width, height: size.height, alignment: .topLeading)
		}
	}

	private var instructionPanel: some View {
		Text("Drag the box, its corners, or the map to frame the geofence area")
			.font(.caption)
			.foregroundStyle(.secondary)
			.multilineTextAlignment(.center)
			.padding()
			.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
			.padding(.horizontal, 12)
			.padding(.bottom, 12)
	}

	private func handlePosition(_ corner: Corner) -> CGPoint {
		switch corner {
		case .topLeading: return CGPoint(x: selectionRect.minX, y: selectionRect.minY)
		case .topTrailing: return CGPoint(x: selectionRect.maxX, y: selectionRect.minY)
		case .bottomLeading: return CGPoint(x: selectionRect.minX, y: selectionRect.maxY)
		case .bottomTrailing: return CGPoint(x: selectionRect.maxX, y: selectionRect.maxY)
		}
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

	/// The on-map area the selection rectangle must stay inside, leaving room for the
	/// instruction panel and the corner handles at the screen edges.
	private func usableRect(in size: CGSize) -> CGRect {
		let top: CGFloat = 16
		let side: CGFloat = 14
		let bottomInset: CGFloat = 120
		let minX = side
		let maxX = max(minX + minRectSize, size.width - side)
		let minY = top
		let maxY = max(minY + minRectSize, size.height - bottomInset)
		return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
	}

	private func initRect(proxy: MapProxy, size: CGSize) {
		guard selectionRect == .zero, size.width > 0, size.height > 0 else { return }
		// When editing an existing box, frame the selection rectangle on that box so tapping
		// Done without dragging preserves it instead of saving the generic default inset.
		if let existing = initialBounds, let rect = rect(for: existing, proxy: proxy, size: size) {
			selectionRect = normalizedClamped(rect.minX, rect.minY, rect.maxX, rect.maxY, in: size)
			return
		}
		let area = usableRect(in: size)
		selectionRect = (area.width > 120 && area.height > 120) ? area.insetBy(dx: 30, dy: 30) : area
	}

	/// Projects a geographic box onto the view's local coordinate space. Prefers the exact
	/// `MapProxy.convert`; falls back to the current region's linear projection when the proxy
	/// isn't ready yet, and returns nil if neither is available (caller uses the inset default).
	private func rect(for b: GeoBounds, proxy: MapProxy, size: CGSize) -> CGRect? {
		let northWest = CLLocationCoordinate2D(latitude: b.maxLat, longitude: b.minLon)
		let southEast = CLLocationCoordinate2D(latitude: b.minLat, longitude: b.maxLon)
		if let nw = proxy.convert(northWest, to: .local), let se = proxy.convert(southEast, to: .local) {
			return CGRect(x: min(nw.x, se.x), y: min(nw.y, se.y), width: abs(se.x - nw.x), height: abs(se.y - nw.y))
		}
		guard let region = currentRegion, size.width > 0, size.height > 0 else { return nil }
		let leftLon = region.center.longitude - region.span.longitudeDelta / 2
		let topLat = region.center.latitude + region.span.latitudeDelta / 2
		let lonPerPx = region.span.longitudeDelta / size.width
		let latPerPx = region.span.latitudeDelta / size.height
		guard lonPerPx > 0, latPerPx > 0 else { return nil }
		return CGRect(
			x: (b.minLon - leftLon) / lonPerPx,
			y: (topLat - b.maxLat) / latPerPx,
			width: (b.maxLon - b.minLon) / lonPerPx,
			height: (b.maxLat - b.minLat) / latPerPx
		)
	}

	private func clampRect(proxy: MapProxy, to size: CGSize) {
		guard size.width > 0, size.height > 0 else { return }
		if selectionRect == .zero { initRect(proxy: proxy, size: size); return }
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

	/// Converts the selection rectangle into geographic bounds. Prefers `MapProxy.convert`;
	/// falls back to projecting onto the current region when the proxy isn't ready yet.
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
}
