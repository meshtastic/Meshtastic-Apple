//
//  ClusterMapView.swift
//  Meshtastic
//
//  SELF-CONTAINED PROOF OF CONCEPT — a declarative, data-driven SwiftUI wrapper over UIKit's
//  `MKMapView`. It gives a `Map`-like call site (pass `items` + a `@ViewBuilder` per annotation)
//  while keeping the three things SwiftUI's own `Map` can't do:
//
//    2. Native MapKit CLUSTERING (`clusteringIdentifier`) with a SwiftUI cluster badge.
//    3. Precise annotation-view REUSE + Identifiable-id DIFFING (no flicker on update).
//
//  This file is standalone and does NOT touch the production `MeshMap`. It only REUSES symbols
//  that already ship in the app target:
//
//    • OfflineTileSource / OfflineTileSourceFactory.source(for:)  (Helpers/Map/MBTilesArchive.swift)
//    • GeoBounds                                                    (Helpers/Map/PMTilesArchive.swift)
//    • AnimatedNodePin / CircleText / UIColor(hex: UInt32)          (node pin styling — demo only)
//
//  HOSTING APPROACH: SwiftUI annotation (and cluster) views are hosted inside `MKAnnotationView`
//  via `UIHostingConfiguration` (iOS 16+). `MKAnnotationView` is a plain `UIView` and does NOT adopt
//  `UIContentConfiguration`, so we cannot assign `view.contentConfiguration = …` directly (that is a
//  cell-only API). Instead we call the public `UIHostingConfiguration().makeContentView()`, which
//  returns a self-sizing `UIView & UIContentView`, embed it ONCE, and only swap its `.configuration`
//  on reuse — so the SwiftUI host (and any running animation, e.g. the pulse) survives recycling.
//
//  Target: iOS 17+. `PulsingCircle` inside `AnimatedNodePin` self-gates to iOS 18.
//

import MapKit
import OSLog
import SwiftUI

// MARK: - Basemap configuration

/// Declarative basemap config applied to the MKMapView (Apple basemap type + controls). The offline
/// raster `.pmtiles` overlay (when `tilesURL` is set) draws ON TOP of whatever this selects.
struct ClusterMapConfiguration: Equatable {
	var layer: MapLayer = .standard
	var showsTraffic = false
	var showsPointsOfInterest = false
	var showsUserLocation = true
	var showsScale = true
	var showsCompass = true
	var showsPitchControl = true
	/// Bottom inset (pts, from the safe area) for the custom compass + pitch controls, so callers can
	/// lift them above an on-screen button bar.
	var controlsBottomInset: CGFloat = 0
}

// MARK: - Overlays (polylines / polygons / circles)

/// How to draw a `ClusterMapOverlay` (constant-width strokes; no casing).
struct ClusterMapOverlayStyle {
	var strokeUIColor: UIColor?
	var fillUIColor: UIColor?
	var lineWidth: CGFloat = 1
	var lineDash: [NSNumber]?
	var lineCap: CGLineCap = .round
	var level: MKOverlayLevel = .aboveLabels
}

/// A caller overlay (route polyline, accuracy circle, convex hull, GeoJSON shape) + its style.
/// `id` is the stable identity for diffing. MKOverlay geometry is immutable, so when an overlay's
/// shape changes the caller must pass a NEW `overlay` object for the same `id` (identity diff →
/// remove + re-add). Pass STABLE objects when unchanged (build them into @State, not in `body`).
struct ClusterMapOverlay: Identifiable {
	let id: AnyHashable
	let overlay: MKOverlay
	let style: ClusterMapOverlayStyle
}

/// A standalone, non-clustering map annotation hosting an arbitrary SwiftUI view (route start/finish
/// markers, waypoints, …). Diffed by `id`; never merges into node clusters.
struct ClusterMapDecoration: Identifiable {
	let id: AnyHashable
	let coordinate: CLLocationCoordinate2D
	let content: AnyView
	/// Tapped -> caller handles it (e.g. open the waypoint form). nil = display-only (route markers).
	var onTap: (() -> Void)?
}

// MARK: - Public declarative API

/// A data-driven map. Pass your `items` and a `@ViewBuilder` that turns one item into its annotation
/// view; the wrapper diffs the array by `Identifiable.id`, hosts each view in an `MKAnnotationView`,
/// and (optionally) clusters them. Optionally bind a two-way camera `region` and/or supply an
/// offline `tilesURL` raster basemap.
///
/// ```swift
/// ClusterMapView(items: nodes, region: $region, clustering: true, tilesURL: topoURL) { node in
///     AnimatedNodePin(nodeColor: node.color, shortName: node.short, … )
/// } clusterContent: { count in
///     ClusterBadge(count: count)
/// }
/// ```
struct ClusterMapView<Item: Identifiable, Pin: View, Cluster: View>: UIViewRepresentable {

	/// The data source. Diffed by `Item.ID` on every `updateUIView` — only changed annotations move.
	let items: [Item]
	/// Per-item coordinate. A closure (not a key-path constraint) so items model location freely.
	let coordinate: (Item) -> CLLocationCoordinate2D
	/// Two-way camera binding. A `nil` wrapped value means "don't drive the camera"; supply a real
	/// binding to read the user's pans/zooms back out AND to push programmatic region changes in.
	let region: Binding<MKCoordinateRegion?>?
	/// When true, annotations share a `clusteringIdentifier` so MapKit collapses nearby pins.
	let clustering: Bool
	/// Builds the SwiftUI view for one item's pin.
	@ViewBuilder let pinContent: (Item) -> Pin
	/// Builds the SwiftUI cluster badge from the collapsed member count.
	@ViewBuilder let clusterContent: (Int) -> Cluster
	/// Called when the user taps an item's pin. (Tapping a cluster zooms to fit its members instead.)
	let onSelect: ((Item) -> Void)?
	/// Apple basemap type + map controls. The offline raster overlay (if any) draws on top.
	let configuration: ClusterMapConfiguration
	/// Vector overlays (accuracy circles, convex hull, routes, GeoJSON shapes). Diffed by `id`.
	let overlays: [ClusterMapOverlay]
	/// Offline coverage areas: each draws an accent border + "OFFLINE MAP" capsule.
	let coverageAreas: [GeoBounds]
	/// Standalone non-clustering decorations (route markers, waypoints) hosted over the map.
	let decorations: [ClusterMapDecoration]
	/// Tap / long-press on EMPTY map (not on a pin/marker) -> caller coordinate (create waypoint).
	let onMapTap: ((CLLocationCoordinate2D) -> Void)?
	let onMapLongPress: ((CLLocationCoordinate2D) -> Void)?

	@Environment(\.colorScheme) private var colorScheme

	// MARK: Designated init (full control)

	init(
		items: [Item],
		coordinate: @escaping (Item) -> CLLocationCoordinate2D,
		region: Binding<MKCoordinateRegion?>? = nil,
		clustering: Bool = true,
		onSelect: ((Item) -> Void)? = nil,
		configuration: ClusterMapConfiguration = .init(),
		overlays: [ClusterMapOverlay] = [],
		coverageAreas: [GeoBounds] = [],
		decorations: [ClusterMapDecoration] = [],
		onMapTap: ((CLLocationCoordinate2D) -> Void)? = nil,
		onMapLongPress: ((CLLocationCoordinate2D) -> Void)? = nil,
		@ViewBuilder content pinContent: @escaping (Item) -> Pin,
		@ViewBuilder clusterContent: @escaping (Int) -> Cluster
	) {
		self.items = items
		self.coordinate = coordinate
		self.region = region
		self.clustering = clustering
		self.onSelect = onSelect
		self.configuration = configuration
		self.overlays = overlays
		self.coverageAreas = coverageAreas
		self.decorations = decorations
		self.onMapTap = onMapTap
		self.onMapLongPress = onMapLongPress
		self.pinContent = pinContent
		self.clusterContent = clusterContent
	}

	// MARK: UIViewRepresentable

	func makeCoordinator() -> Coordinator { Coordinator() }

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator
		refreshClosures(on: context.coordinator)

		// Register the reusable view classes ONCE. With registered classes MapKit dequeues + reuses
		// them itself (incl. the cluster MapKit synthesizes); `viewFor` only reconfigures contents.
		mapView.register(HostingAnnotationView.self,
						 forAnnotationViewWithReuseIdentifier: HostingAnnotationView.reuseID)
		mapView.register(HostingClusterView.self,
						 forAnnotationViewWithReuseIdentifier: HostingClusterView.reuseID)
						mapView.register(HostingCoverageLabelView.self,
										 forAnnotationViewWithReuseIdentifier: HostingCoverageLabelView.reuseID)
										mapView.register(HostingDecorationView.self,
														 forAnnotationViewWithReuseIdentifier: HostingDecorationView.reuseID)

														// Map tap / long-press -> caller (create waypoint). The delegate rejects touches that land on an
														// annotation view so pin/marker taps still select normally instead of creating a waypoint.
														let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
														tap.delegate = context.coordinator
														mapView.addGestureRecognizer(tap)
														let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapLongPress(_:)))
														longPress.delegate = context.coordinator
														mapView.addGestureRecognizer(longPress)

		// Apple basemap type + controls.
		context.coordinator.applyConfiguration(configuration, to: mapView)
		context.coordinator.installControls(on: mapView, bottomInset: configuration.controlsBottomInset)

		// Offline raster basemap (optional). Mirrors PMTilesMapView.makeUIView exactly.

		// Vector overlays (circles / hull / routes / GeoJSON), diffed by id.
		context.coordinator.syncOverlays(overlays, on: mapView)
		context.coordinator.syncCoverage(areas: coverageAreas, dark: colorScheme == .dark, on: mapView)
		context.coordinator.syncDecorations(decorations, on: mapView)

		// Initial camera, if the caller drives one. Guarded so we don't echo it back out.
		if let region = region?.wrappedValue {
			context.coordinator.isApplyingExternalRegion = true
			mapView.setRegion(region, animated: false)
			context.coordinator.isApplyingExternalRegion = false
		}

		// Seed the annotations through the same diffing path used by updates.
		context.coordinator.sync(items: items, coordinate: coordinate,
								 clustering: clustering, on: mapView)
		return mapView
	}

	func updateUIView(_ mapView: MKMapView, context: Context) {
		// Keep the coordinator's closures fresh so SwiftUI state captured by the builders stays
		// current on reuse (the representable is recreated each render; the coordinator persists).
		refreshClosures(on: context.coordinator)

		// 0) Apple basemap type + controls (diffed; only re-applied when it actually changed).
		context.coordinator.applyConfiguration(configuration, to: mapView)
		context.coordinator.installControls(on: mapView, bottomInset: configuration.controlsBottomInset)

		// 1) Offline basemap: rebuild only if the URL or the dark/light flag actually changed.

		// 1b) Vector overlays — diffed by id (object-identity change → remove + re-add).
		context.coordinator.syncOverlays(overlays, on: mapView)
		context.coordinator.syncCoverage(areas: coverageAreas, dark: colorScheme == .dark, on: mapView)
		context.coordinator.syncDecorations(decorations, on: mapView)

		// 2) Diff annotations by Identifiable id — add/remove/move ONLY what changed (no flicker).
		context.coordinator.sync(items: items, coordinate: coordinate,
								 clustering: clustering, on: mapView)

		// 3) Push an external region change in — but never while the user is driving the map, and
		//    skip no-op writes. That's the feedback-loop guard (see Coordinator).
		if let region = region?.wrappedValue,
		   !context.coordinator.isUpdatingRegionFromMap,
		   !context.coordinator.regionsApproximatelyEqual(mapView.region, region) {
			context.coordinator.isApplyingExternalRegion = true
			mapView.setRegion(region, animated: true)
			// Cleared in regionDidChangeAnimated; also clear async in case no event fires.
			DispatchQueue.main.async { context.coordinator.isApplyingExternalRegion = false }
		}
	}

	/// Re-capture the SwiftUI builders + camera binding onto the (persistent) coordinator.
	private func refreshClosures(on coordinator: Coordinator) {
		coordinator.pinContent = { AnyView(pinContent($0)) }
		coordinator.clusterContent = { AnyView(clusterContent($0)) }
		coordinator.regionBinding = region
		coordinator.onSelect = onSelect
		coordinator.onMapTap = onMapTap
		coordinator.onMapLongPress = onMapLongPress
	}

	// MARK: - Coordinator (MKMapViewDelegate + diffing + camera sync + offline overlay)

	final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

		/// Builds the hosted SwiftUI pin for an item. Reset each render so captured state is fresh.
		var pinContent: (Item) -> AnyView = { _ in AnyView(EmptyView()) }
		/// Builds the hosted SwiftUI cluster badge for a member count.
		var clusterContent: (Int) -> AnyView = { _ in AnyView(EmptyView()) }
		/// The camera binding, set by the representable each render so the delegate can write back.
		var regionBinding: Binding<MKCoordinateRegion?>?
		/// Called when an item pin is tapped (set each render).
		var onSelect: ((Item) -> Void)?
		/// Empty-map tap / long-press handlers (create waypoint), set each render.
		var onMapTap: ((CLLocationCoordinate2D) -> Void)?
		var onMapLongPress: ((CLLocationCoordinate2D) -> Void)?

		/// id → the backing annotation currently on the map. The single source of truth for diffing.
		private var annotationsByID: [Item.ID: ItemAnnotation<Item>] = [:]

		/// Accent rectangles drawn on each offline coverage box so each offline area reads as a
		/// deliberate feature. Rebuilt when the coverage areas or `dark` change.
		private var coverageOverlays: [MKPolygon] = []
		/// Object-identity set of the coverage borders, for O(1) lookup in `rendererFor`.
		private var coverageOverlayIDs: Set<ObjectIdentifier> = []
		/// The "OFFLINE MAP" capsule annotations; lifecycle mirrors `coverageOverlays`.
		private var coverageLabels: [OfflineCoverageLabelAnnotation] = []
		/// Applied coverage areas + dark flag, so syncCoverage only rebuilds when they change.
		private var coverageAreasApplied: [GeoBounds] = []
		private var coverageDark = false

		// Custom map controls (compass + pitch toggle), pinned bottom-trailing above the button bar.
		private weak var hostMapView: MKMapView?
		private var controlsStack: UIStackView?
		private var controlsBottomConstraint: NSLayoutConstraint?
		/// id → standalone decoration annotation (route markers, waypoints) currently on the map.
		private var decorationsByID: [AnyHashable: DecorationAnnotation] = [:]

		/// Last-applied basemap config, so we only touch `preferredConfiguration` when it changed
		/// (re-applying it resets the rendered map and is visibly expensive).
		private var appliedConfiguration: ClusterMapConfiguration?

		// Vector overlay diffing state.
		/// id → the caller overlay currently on the map (source of truth for overlay diffing).
		private var overlaysByID: [AnyHashable: ClusterMapOverlay] = [:]
		/// Per-MKOverlay style, keyed by object identity, for O(1) lookup in `rendererFor`.
		private var styleByOverlay: [ObjectIdentifier: ClusterMapOverlayStyle] = [:]

		// Camera feedback-loop guards.
		/// True while WE push an external region in (so the resulting `regionDidChange` callback
		/// doesn't write back out and ping-pong).
		var isApplyingExternalRegion = false
		/// True for the duration of a user-driven region write-back (so an interleaved update won't
		/// fight the gesture by re-applying the binding mid-pan).
		var isUpdatingRegionFromMap = false

		/// Shared clustering identifier — all clustered item annotations use the same one so MapKit
		/// groups them. (Computed, not stored: the Coordinator is nested in the generic
		/// `ClusterMapView`, and Swift forbids static STORED properties on generic types.)
		private static var clusterID: String { "ClusterMapView.item" }

		// MARK: Basemap configuration (Apple map type + controls)

		/// Apply the Apple basemap type + control flags, diffing so it's only set when changed.
		func applyConfiguration(_ config: ClusterMapConfiguration, to mapView: MKMapView) {
			guard appliedConfiguration != config else { return }
			let firstApply = appliedConfiguration == nil
			let typeChanged = appliedConfiguration?.layer != config.layer
				|| appliedConfiguration?.showsTraffic != config.showsTraffic
				|| appliedConfiguration?.showsPointsOfInterest != config.showsPointsOfInterest
			appliedConfiguration = config

			if firstApply || typeChanged {
				let poi: MKPointOfInterestFilter = config.showsPointsOfInterest ? .includingAll : .excludingAll
				switch config.layer {
				case .standard, .offline:
					// Offline tiles are now an independent overlay (drawn on top of whatever base is
					// selected), so a stray `.offline` base value just maps to the clean Standard base.
					let standard = MKStandardMapConfiguration(elevationStyle: .realistic)
					standard.pointOfInterestFilter = poi
					standard.showsTraffic = config.showsTraffic
					mapView.preferredConfiguration = standard
				case .hybrid:
					let hybrid = MKHybridMapConfiguration(elevationStyle: .realistic)
					hybrid.pointOfInterestFilter = poi
					hybrid.showsTraffic = config.showsTraffic
					mapView.preferredConfiguration = hybrid
				case .satellite:
					mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
				}
			}

			mapView.showsUserLocation = config.showsUserLocation
			mapView.showsScale = config.showsScale
			// A custom compass + pitch toggle are installed in `installControls` (bottom-trailing, above
			// the caller's button bar); the built-in top-right compass is disabled there.
			mapView.isPitchEnabled = config.showsPitchControl
		}

		// MARK: Custom controls (compass + pitch toggle, bottom-trailing above the button bar)

		/// Installs (once) a custom compass + pitch toggle pinned to the map's bottom-trailing safe area,
		/// lifted by `bottomInset` so they clear the caller's button bar. Disables the built-in compass.
		func installControls(on mapView: MKMapView, bottomInset: CGFloat) {
			hostMapView = mapView
			mapView.showsCompass = false
			if let controlsBottomConstraint {
				controlsBottomConstraint.constant = -bottomInset
				return
			}
			let compass = MKCompassButton(mapView: mapView)
			compass.compassVisibility = .adaptive

			let pitch = UIButton(type: .system)
			pitch.setImage(UIImage(systemName: "view.3d") ?? UIImage(systemName: "cube"), for: .normal)
			pitch.tintColor = .label
			pitch.backgroundColor = UIColor.tertiarySystemBackground.withAlphaComponent(0.92)
			pitch.layer.cornerRadius = 8
			pitch.layer.shadowColor = UIColor.black.cgColor
			pitch.layer.shadowOpacity = 0.2
			pitch.layer.shadowRadius = 2
			pitch.layer.shadowOffset = CGSize(width: 0, height: 1)
			pitch.translatesAutoresizingMaskIntoConstraints = false
			pitch.addTarget(self, action: #selector(togglePitch), for: .touchUpInside)
			NSLayoutConstraint.activate([
				pitch.widthAnchor.constraint(equalToConstant: 44),
				pitch.heightAnchor.constraint(equalToConstant: 44)
			])

			let stack = UIStackView(arrangedSubviews: [pitch, compass])
			stack.axis = .vertical
			stack.spacing = 10
			stack.alignment = .center
			stack.translatesAutoresizingMaskIntoConstraints = false
			mapView.addSubview(stack)
			let bottom = stack.bottomAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.bottomAnchor, constant: -bottomInset)
			NSLayoutConstraint.activate([
				stack.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -12),
				bottom
			])
			controlsStack = stack
			controlsBottomConstraint = bottom
		}

		/// Toggle the camera between flat (2D) and pitched (3D), like the old SwiftUI `MapPitchToggle`.
		@objc func togglePitch() {
			guard let mapView = hostMapView else { return }
			let current = mapView.camera
			let pitched = current.pitch > 1
			let camera = MKMapCamera(
				lookingAtCenter: mapView.centerCoordinate,
				fromDistance: current.centerCoordinateDistance,
				pitch: pitched ? 0 : 55,
				heading: current.heading
			)
			mapView.setCamera(camera, animated: true)
		}

		// MARK: Offline basemap (mirrors PMTilesMapView's swap-on-dark pattern)

		/// Adds the offline overlay, or rebuilds it when the URL or dark flag changed. Idempotent:
		/// safe to call every `updateUIView`. The `source` is retained, so a light/dark switch only
		/// rebuilds the cheap overlay wrapper, never re-opens the archive.

		// MARK: Offline coverage decoration (accent border + "OFFLINE MAP" capsule)

		/// Draws (or clears) the accent coverage border + capsule, driven by an explicit bounds param so it
		/// aligns exactly with the caller's offline content (no tile-grid mismatch). Rebuilt only when the
		/// bounds or the dark flag change; recolors via `coverageDark`.
		func syncCoverage(areas: [GeoBounds], dark: Bool, on mapView: MKMapView) {
			if coverageAreasApplied == areas, coverageDark == dark { return }
			coverageAreasApplied = areas
			coverageDark = dark
			if !coverageOverlays.isEmpty { mapView.removeOverlays(coverageOverlays) }
			coverageOverlays = []
			coverageOverlayIDs = []
			if !coverageLabels.isEmpty { mapView.removeAnnotations(coverageLabels) }
			coverageLabels = []
			for bounds in areas {
				let corners = [
					CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon),
					CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.maxLon),
					CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon),
					CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.minLon)
				]
				let border = MKPolygon(coordinates: corners, count: corners.count)
				coverageOverlays.append(border)
				coverageOverlayIDs.insert(ObjectIdentifier(border))
				mapView.addOverlay(border, level: .aboveLabels)
				let labelCoord = CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: (bounds.minLon + bounds.maxLon) / 2)
				let label = OfflineCoverageLabelAnnotation(coordinate: labelCoord)
				coverageLabels.append(label)
				mapView.addAnnotation(label)
			}
		}

		// MARK: Overlay diffing (circles / hull / routes / GeoJSON)

		/// Reconcile caller overlays with the map by `id`. Same id + same object = unchanged. Same id
		/// + DIFFERENT object (geometry/style changed) = remove old + add new. Never touches the
		/// retained offline `tileOverlay` (that's owned by `installTileOverlay`).
		func syncOverlays(_ overlays: [ClusterMapOverlay], on mapView: MKMapView) {
			var seen = Set<AnyHashable>()
			seen.reserveCapacity(overlays.count)
			var toAdd: [ClusterMapOverlay] = []
			var toRemove: [MKOverlay] = []

			for entry in overlays {
				seen.insert(entry.id)
				if let existing = overlaysByID[entry.id] {
					if existing.overlay === entry.overlay { continue } // unchanged
					toRemove.append(existing.overlay)
					styleByOverlay[ObjectIdentifier(existing.overlay)] = nil
				}
				overlaysByID[entry.id] = entry
				styleByOverlay[ObjectIdentifier(entry.overlay)] = entry.style
				toAdd.append(entry)
			}

			// Removals: any tracked id not present this pass (only OUR overlays — never the tileOverlay).
			for id in overlaysByID.keys where !seen.contains(id) {
				if let gone = overlaysByID.removeValue(forKey: id) {
					styleByOverlay[ObjectIdentifier(gone.overlay)] = nil
					toRemove.append(gone.overlay)
				}
			}

			if !toRemove.isEmpty { mapView.removeOverlays(toRemove) }
			for entry in toAdd { mapView.addOverlay(entry.overlay, level: entry.style.level) }
		}

		// MARK: Decoration diffing (standalone non-clustering markers)

		/// Reconcile standalone (non-clustering) decoration annotations by id — add/remove/move + refresh
		/// content in place, mirroring `sync` but for caller-hosted markers that must never cluster.
		func syncDecorations(_ decorations: [ClusterMapDecoration], on mapView: MKMapView) {
			var seen = Set<AnyHashable>()
			seen.reserveCapacity(decorations.count)
			var toAdd: [DecorationAnnotation] = []
			for deco in decorations {
				seen.insert(deco.id)
				if let existing = decorationsByID[deco.id] {
					existing.content = deco.content
					existing.onTap = deco.onTap
					if !Self.coordinatesEqual(existing.coordinate, deco.coordinate) {
						existing.coordinate = deco.coordinate
					}
					if let view = mapView.view(for: existing) as? HostingDecorationView {
						view.configure(content: deco.content)
					}
				} else {
					let annotation = DecorationAnnotation(id: deco.id, coordinate: deco.coordinate, content: deco.content)
					annotation.onTap = deco.onTap
					decorationsByID[deco.id] = annotation
					toAdd.append(annotation)
				}
			}
			let removed = decorationsByID.keys.filter { !seen.contains($0) }
			if !removed.isEmpty {
				let gone = removed.compactMap { decorationsByID.removeValue(forKey: $0) }
				mapView.removeAnnotations(gone)
			}
			if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }
		}

		// MARK: Annotation diffing

		/// Reconcile on-map annotations with `items` by `Item.ID`, touching ONLY what changed.
		///
		///  • New id      → make an `ItemAnnotation`, add it.
		///  • Removed id  → remove its annotation.
		///  • Existing id → update the item in place; move the coordinate ONLY if it changed.
		///
		/// We never `removeAnnotations(all)` + re-add — that flickers and re-runs cluster layout.
		/// Moves mutate the KVO-compliant `coordinate` in place so MapKit animates the existing view.
		func sync(
			items: [Item],
			coordinate: (Item) -> CLLocationCoordinate2D,
			clustering: Bool,
			on mapView: MKMapView
		) {
			let wantClusterID: String? = clustering ? Self.clusterID : nil
			var seen = Set<Item.ID>()
			seen.reserveCapacity(items.count)
			var toAdd: [ItemAnnotation<Item>] = []
			var toReadd: [ItemAnnotation<Item>] = []

			for item in items {
				let id = item.id
				seen.insert(id)
				let coord = coordinate(item)

				if let existing = annotationsByID[id] {
					// Update in place — keeps the same MapKit view (no flicker).
					existing.item = item
					if !Self.coordinatesEqual(existing.coordinate, coord) {
						existing.coordinate = coord // KVO → MapKit animates the move
					}
					// Toggling clustering at runtime requires re-add: clusteringIdentifier is only
					// honored when the annotation is added.
					if existing.clusteringIdentifier != wantClusterID {
						existing.clusteringIdentifier = wantClusterID
						mapView.removeAnnotation(existing)
						toReadd.append(existing)
					} else if let view = mapView.view(for: existing) as? HostingAnnotationView {
						// Refresh a currently-visible view so it reflects the new item snapshot
						// (e.g. an online/offline change).
						view.configure(content: pinContent(item))
					}
				} else {
					let annotation = ItemAnnotation(item: item, coordinate: coord,
													clusteringIdentifier: wantClusterID)
					annotationsByID[id] = annotation
					toAdd.append(annotation)
				}
			}

			// Removals: any tracked id not present this pass.
			let removedIDs = annotationsByID.keys.filter { !seen.contains($0) }
			if !removedIDs.isEmpty {
				let removed = removedIDs.compactMap { annotationsByID.removeValue(forKey: $0) }
				mapView.removeAnnotations(removed)
			}
			if !toReadd.isEmpty { mapView.addAnnotations(toReadd) }
			if !toAdd.isEmpty { mapView.addAnnotations(toAdd) } // MapKit batches & clusters these
		}

		// MARK: MKMapViewDelegate — viewFor hosts SwiftUI in MKAnnotationView

		func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
			// MapKit's blue user-location dot — let MapKit own it.
			if annotation is MKUserLocation { return nil }

			// A cluster MapKit synthesized from our clustered annotations.
			if let cluster = annotation as? MKClusterAnnotation {
				let view = mapView.dequeueReusableAnnotationView(
					withIdentifier: HostingClusterView.reuseID, for: cluster) as? HostingClusterView
				view?.configure(content: clusterContent(cluster.memberAnnotations.count))
				return view
			}

			// One of our item annotations.
			// The offline coverage capsule label (standalone, non-selecting).
			// A standalone decoration (route marker / waypoint), hosted but never clustered.
			if let deco = annotation as? DecorationAnnotation {
				let view = mapView.dequeueReusableAnnotationView(
					withIdentifier: HostingDecorationView.reuseID, for: deco)
				(view as? HostingDecorationView)?.configure(content: deco.content)
				view.isEnabled = (deco.onTap != nil) // tappable for waypoints; route markers stay inert
				return view
			}

			if annotation is OfflineCoverageLabelAnnotation {
				let view = mapView.dequeueReusableAnnotationView(
					withIdentifier: HostingCoverageLabelView.reuseID, for: annotation)
				(view as? HostingCoverageLabelView)?.configure(content: makeOfflineCoverageLabel(dark: coverageDark))
				return view
			}
			
			if let item = annotation as? ItemAnnotation<Item> {
				let view = mapView.dequeueReusableAnnotationView(
					withIdentifier: HostingAnnotationView.reuseID, for: item) as? HostingAnnotationView
				// `for:` already assigned `view.annotation = item`. Mirror clusteringIdentifier onto
				// the VIEW too — MapKit reads it from the annotation view when forming clusters.
				view?.clusteringIdentifier = item.clusteringIdentifier
				view?.configure(content: pinContent(item.item))
				return view
			}

			return nil
		}

		// MARK: Selection — tap a pin → onSelect; tap a cluster → zoom to fit its members

		func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
			if let cluster = view.annotation as? MKClusterAnnotation {
				// Expand a cluster: zoom to the bounding rect of its members.
				let rect = cluster.memberAnnotations.reduce(MKMapRect.null) { acc, member in
					acc.union(MKMapRect(origin: MKMapPoint(member.coordinate), size: MKMapSize(width: 0, height: 0)))
				}
				if !rect.isNull {
					let padded = rect.insetBy(dx: -rect.size.width * 0.3 - 1, dy: -rect.size.height * 0.3 - 1)
					mapView.setVisibleMapRect(padded, animated: true)
				}
				mapView.deselectAnnotation(cluster, animated: false)
				return
			}
			if let deco = view.annotation as? DecorationAnnotation {
				deco.onTap?()
				mapView.deselectAnnotation(deco, animated: false)
				return
			}
			if let annotation = view.annotation as? ItemAnnotation<Item> {
				onSelect?(annotation.item)
				// Immediate deselect so re-tapping the SAME pin fires again (sheet binding de-dups).
				mapView.deselectAnnotation(annotation, animated: false)
			}
		}

		// MARK: Map gestures (create waypoint) + delegate
		@objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
			guard gesture.state == .ended, let mapView = gesture.view as? MKMapView else { return }
			onMapTap?(mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView))
		}
		@objc func handleMapLongPress(_ gesture: UILongPressGestureRecognizer) {
			guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
			onMapLongPress?(mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView))
		}
		/// Reject the gesture when the touch lands on an annotation view, so tapping a pin/marker selects
		/// it (and doesn't also create a waypoint); empty-map touches pass through.
		func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
			guard let mapView = gestureRecognizer.view as? MKMapView else { return true }
			var hit = mapView.hitTest(touch.location(in: mapView), with: nil)
			while let view = hit, view !== mapView {
				if view is MKAnnotationView { return false }
				hit = view.superview
			}
			return true
		}
		func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
			true // coexist with MapKit's own pan/zoom recognizers
		}

		// MARK: Overlay renderer

		func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
			// Offline coverage border — accent rectangle, recolored per appearance.
			if coverageOverlayIDs.contains(ObjectIdentifier(overlay)), let polygon = overlay as? MKPolygon {
				let renderer = MKPolygonRenderer(polygon: polygon)
				renderer.strokeColor = coverageDark ? .systemCyan : .systemBlue
				renderer.fillColor = .clear
				renderer.lineWidth = 4
				renderer.lineJoin = .round
				return renderer
			}
			// Styled caller overlay (circle / polyline / polygon), style looked up by object identity.
			let style = styleByOverlay[ObjectIdentifier(overlay)] ?? ClusterMapOverlayStyle()
			let renderer: MKOverlayPathRenderer
			switch overlay {
			case let circle as MKCircle: renderer = MKCircleRenderer(circle: circle)
			case let polygon as MKPolygon: renderer = MKPolygonRenderer(polygon: polygon)
			case let polyline as MKPolyline: renderer = MKPolylineRenderer(polyline: polyline)
			case let multi as MKMultiPolyline: renderer = MKMultiPolylineRenderer(multiPolyline: multi)
			case let multi as MKMultiPolygon: renderer = MKMultiPolygonRenderer(multiPolygon: multi)
			default: return MKOverlayRenderer(overlay: overlay)
			}
			renderer.strokeColor = style.strokeUIColor
			renderer.fillColor = style.fillUIColor
			renderer.lineWidth = style.lineWidth
			renderer.lineDashPattern = style.lineDash
			renderer.lineCap = style.lineCap
			return renderer
		}

		// MARK: Camera write-back (user gestures → region binding), loop-guarded

		func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
			// Ignore the callback caused by our own external write (guard #1).
			guard !isApplyingExternalRegion else {
				isApplyingExternalRegion = false
				return
			}
			guard let regionBinding else { return }
			let newRegion = mapView.region
			// Skip no-op writes so we don't thrash SwiftUI state (guard #2).
			if let current = regionBinding.wrappedValue,
			   regionsApproximatelyEqual(current, newRegion) { return }
			isUpdatingRegionFromMap = true
			defer { isUpdatingRegionFromMap = false }
			regionBinding.wrappedValue = newRegion
		}

		// MARK: Helpers

		static func coordinatesEqual(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
			// ~1e-7° (~1 cm) is below MapKit's display resolution — don't churn on float noise.
			abs(a.latitude - b.latitude) < 1e-7 && abs(a.longitude - b.longitude) < 1e-7
		}

		/// Loose equality so float jitter from MapKit doesn't count as "the binding changed".
		/// (`MKCoordinateRegion` is intentionally not made `Equatable` — a fuzzy global `==` would
		/// silently weaken every guard that uses it.)
		func regionsApproximatelyEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
			let centerTolerance = 1e-5, spanTolerance = 1e-5
			return abs(a.center.latitude - b.center.latitude) < centerTolerance &&
				   abs(a.center.longitude - b.center.longitude) < centerTolerance &&
				   abs(a.span.latitudeDelta - b.span.latitudeDelta) < spanTolerance &&
				   abs(a.span.longitudeDelta - b.span.longitudeDelta) < spanTolerance
		}
	}
}

// MARK: - Convenience initializer: default cluster badge

extension ClusterMapView where Cluster == ClusterBadge {
	/// `Map`-like init that uses the built-in count badge for clusters, so callers only supply the pin.
	init(
		items: [Item],
		coordinate: @escaping (Item) -> CLLocationCoordinate2D,
		region: Binding<MKCoordinateRegion?>? = nil,
		clustering: Bool = true,
		onSelect: ((Item) -> Void)? = nil,
		configuration: ClusterMapConfiguration = .init(),
		overlays: [ClusterMapOverlay] = [],
		coverageAreas: [GeoBounds] = [],
		decorations: [ClusterMapDecoration] = [],
		onMapTap: ((CLLocationCoordinate2D) -> Void)? = nil,
		onMapLongPress: ((CLLocationCoordinate2D) -> Void)? = nil,
		@ViewBuilder content pinContent: @escaping (Item) -> Pin
	) {
		self.init(items: items,
				  coordinate: coordinate,
				  region: region,
				  clustering: clustering,
				  onSelect: onSelect,
				  configuration: configuration,
				  overlays: overlays,
				coverageAreas: coverageAreas,
				decorations: decorations,
				onMapTap: onMapTap,
				onMapLongPress: onMapLongPress,
				  content: pinContent,
				  clusterContent: { ClusterBadge(count: $0) })
	}
}

// MARK: - Backing MKAnnotation that carries the item by identity

/// One MapKit annotation per caller item. MapKit requires `MKAnnotation` to be a class, so this is
/// a reference type carrying the strongly-typed `item` plus its stable id. `coordinate` is
/// `@objc dynamic` so mutating it in place is KVO-observed by MapKit and animates the existing view.
private final class ItemAnnotation<Item: Identifiable>: NSObject, MKAnnotation {
	@objc dynamic var coordinate: CLLocationCoordinate2D
	/// Current item, replaced in place on update so the hosted view refreshes without the annotation
	/// losing its MapKit identity (and thus its on-screen view + cluster membership).
	var item: Item
	let identifier: Item.ID
	/// Non-nil enables clustering for this annotation; MapKit groups equal identifiers.
	var clusteringIdentifier: String?

	init(item: Item, coordinate: CLLocationCoordinate2D, clusteringIdentifier: String?) {
		self.item = item
		self.identifier = item.id
		self.coordinate = coordinate
		self.clusteringIdentifier = clusteringIdentifier
		super.init()
	}
}

/// Type-erased hook so `HostingAnnotationView` can read `clusteringIdentifier` off any
/// `ItemAnnotation<…>` without naming the concrete `Item`.
private protocol AnyClusteredAnnotation {
	var anyClusteringIdentifier: String? { get }
}
extension ItemAnnotation: AnyClusteredAnnotation {
	var anyClusteringIdentifier: String? { clusteringIdentifier }
}

// MARK: - Hosting annotation views (SwiftUI inside MKAnnotationView via UIHostingConfiguration)
//
// NOTE: `MKAnnotationView` is NOT a `contentConfiguration` host (only cells / list content views
// are), so `view.contentConfiguration = UIHostingConfiguration { … }` does NOT compile against it.
// We instead call `UIHostingConfiguration().makeContentView()` — a public iOS-16 API returning a
// self-sizing `UIView & UIContentView` — and embed THAT once, swapping only its `.configuration`
// on reuse so the SwiftUI host (and any running animation) survives recycling.

/// Common base: keeps one hosting content view alive and re-applies a fresh `UIHostingConfiguration`
/// on each `configure(content:)`, sizing the annotation view to the SwiftUI content.
private class HostingAnnotationViewBase: MKAnnotationView {
	/// The persistent `UIView & UIContentView` made from a `UIHostingConfiguration`.
	private var hostContentView: (UIView & UIContentView)?

	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
		// Let the SwiftUI content extend beyond the view's nominal bounds (e.g. the 50pt pulse halo).
		clipsToBounds = false
		collisionMode = .circle
		backgroundColor = .clear
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	/// (Re)host `content`. Builds the hosting content view once; afterwards just swaps its
	/// `configuration`, so the SwiftUI host persists across reuse.
	func configure(content: AnyView) {
		let configuration = UIHostingConfiguration { content }.margins(.all, 0)
		if let hostContentView {
			hostContentView.configuration = configuration
		} else {
			let view = configuration.makeContentView()
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
			NSLayoutConstraint.activate([
				view.centerXAnchor.constraint(equalTo: centerXAnchor),
				view.centerYAnchor.constraint(equalTo: centerYAnchor)
			])
			hostContentView = view
		}
		// Size the annotation view to the hosted content so hit-testing / anchoring are correct.
		let target = hostContentView?.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
			?? CGSize(width: 40, height: 40)
		frame = CGRect(origin: frame.origin, size: CGSize(width: max(target.width, 1),
														  height: max(target.height, 1)))
		centerOffset = .zero // MapKit places the view's CENTER on the coordinate — what we want.
	}
}

/// Hosts an arbitrary SwiftUI pin. Registered with the map so MapKit dequeues / reuses it.
private final class HostingAnnotationView: HostingAnnotationViewBase {
	static let reuseID = "ClusterMapView.pin"

	/// MapKit reads `clusteringIdentifier` off the annotation VIEW when forming clusters; mirror the
	/// annotation's identifier onto the view whenever the (reused) annotation is reassigned.
	override var annotation: MKAnnotation? {
		didSet {
			if let clustered = annotation as? AnyClusteredAnnotation {
				clusteringIdentifier = clustered.anyClusteringIdentifier
			}
		}
	}
}

/// Hosts an arbitrary SwiftUI cluster badge.
private final class HostingClusterView: HostingAnnotationViewBase {
	static let reuseID = "ClusterMapView.cluster"

	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
		displayPriority = .defaultHigh // clusters win over individual pins when they overlap
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Offline coverage label (the "OFFLINE MAP" capsule, hosted like a pin)

/// Standalone, non-clustering, non-selectable annotation marking the offline coverage area with the
/// "OFFLINE MAP" capsule tab (mirrors the SwiftUI map's label).
/// Standalone, non-clustering annotation carrying an arbitrary SwiftUI view by value.
private final class DecorationAnnotation: NSObject, MKAnnotation {
	let id: AnyHashable
	@objc dynamic var coordinate: CLLocationCoordinate2D
	var content: AnyView
	var onTap: (() -> Void)?
	init(id: AnyHashable, coordinate: CLLocationCoordinate2D, content: AnyView) {
		self.id = id; self.coordinate = coordinate; self.content = content
	}
}

/// Hosts a caller decoration's SwiftUI view. Never clusters.
private final class HostingDecorationView: HostingAnnotationViewBase {
	static let reuseID = "ClusterMapView.decoration"
	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
		// isEnabled is set per-decoration in viewFor (tappable for waypoints, inert for route markers).
	}
	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class OfflineCoverageLabelAnnotation: NSObject, MKAnnotation {
	@objc dynamic var coordinate: CLLocationCoordinate2D
	init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// Hosts the offline coverage capsule label. Not a tap target and never decluttered away.
private final class HostingCoverageLabelView: HostingAnnotationViewBase {
	static let reuseID = "ClusterMapView.coverageLabel"
	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
		isEnabled = false           // a label, not selectable
		displayPriority = .required // never hidden by decluttering
	}
	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The "OFFLINE MAP" capsule view shown on the offline coverage area, matching the SwiftUI map.
private func makeOfflineCoverageLabel(dark: Bool) -> AnyView {
	let accent: Color = dark ? .cyan : .blue
	return AnyView(
		Text("OFFLINE MAP")
			.font(.system(size: 11, weight: .heavy))
			.tracking(0.5)
			.foregroundStyle(.white)
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(Capsule().fill(accent))
			.shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
	)
}

// MARK: - Default cluster badge (a SwiftUI view, hosted just like the pins)

/// The built-in cluster count badge used by the convenience initializer.
struct ClusterBadge: View {
	let count: Int

	var body: some View {
		Text("\(count)")
			.font(.system(size: 15, weight: .bold, design: .rounded))
			.foregroundStyle(.white)
			.padding(8)
			.frame(minWidth: 34, minHeight: 34)
			.background(
				Circle().fill(Color.accentColor)
					.overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
			)
			.shadow(color: .black.opacity(0.25), radius: 2, y: 1)
	}
}
