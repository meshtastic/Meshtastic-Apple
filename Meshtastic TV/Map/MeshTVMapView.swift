//
//  MeshTVMapView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Fresh, minimal MKMapView wrapper for tvOS. Deliberately does NOT port the iOS
//  `ClusterMapView` (welded to touch gestures, MKUserTrackingButton and SwiftData).
//  No device GPS on tvOS, so `showsUserLocation` is off and we only plot the
//  reported positions of other nodes. Selection is driven by the focus engine
//  (clicking a pin) and by the side list via `selectedNodeNum`.
//
//  Node pins match the iOS map's look: a circle colored by `UIColor(hex: nodeNum)`
//  with the node's short name inside (see `CircleText` / `AnimatedNodePin`), and
//  clusters render as an accent circle with a member count (see `ClusterBadge`).
//

import MapKit
import SwiftUI

/// MKAnnotation for a mesh node. `num` lets us diff annotations without rebuilding.
final class NodeAnnotation: NSObject, MKAnnotation {
	/// The node this pin draws — the lowest-numbered member when several share a
	/// coordinate.
	var num: UInt32
	dynamic var coordinate: CLLocationCoordinate2D
	var title: String?
	var subtitle: String?
	var shortName: String
	/// How many nodes report this exact coordinate. 1 for an ordinary pin; above
	/// that the view draws a count badge instead of the node marker.
	var memberCount: Int = 1

	init(node: MeshNode, coordinate: CLLocationCoordinate2D, memberCount: Int = 1) {
		self.num = node.num
		self.coordinate = coordinate
		self.title = node.displayName
		self.subtitle = node.shortName
		self.shortName = node.shortName
		self.memberCount = memberCount
	}
}

/// iOS-map-style node pin: colored circle keyed to the node number, short name
/// inside, white ring. UIKit-drawn (no SwiftUI hosting) so MapKit reuse on tvOS
/// stays cheap and the view is focus-engine selectable.
final class NodeCircleAnnotationView: MKAnnotationView {
	static let reuseID = "nodeCircle"
	private static let diameter: CGFloat = 64   // 10-foot UI: larger than iOS's 40

	private let circle = UIView()
	private let label = UILabel()

	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
		let d = Self.diameter
		frame = CGRect(x: 0, y: 0, width: d, height: d)
		collisionMode = .circle
		canShowCallout = true

		circle.frame = bounds
		circle.layer.cornerRadius = d / 2
		circle.layer.borderWidth = 3
		circle.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
		circle.layer.shadowColor = UIColor.black.cgColor
		circle.layer.shadowOpacity = 0.35
		circle.layer.shadowRadius = 3
		circle.layer.shadowOffset = CGSize(width: 0, height: 1)
		// Pre-computed shadow shape: without it, every pin pays an offscreen
		// shadow pass per frame during map animations — with ~100 pins that
		// drops frames and renders as visual noise mid-flight.
		circle.layer.shadowPath = UIBezierPath(ovalIn: circle.bounds).cgPath
		addSubview(circle)

		label.frame = bounds.insetBy(dx: 6, dy: 6)
		label.textAlignment = .center
		label.font = .systemFont(ofSize: 20, weight: .bold)
		label.adjustsFontSizeToFitWidth = true
		label.minimumScaleFactor = 0.4
		label.baselineAdjustment = .alignCenters
		circle.addSubview(label)
	}

	required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override var annotation: MKAnnotation? {
		didSet {
			// Only on (re)assignment — never on live updates. Reassigning
			// `clusteringIdentifier` on every data tick makes MapKit tear down and
			// rebuild annotation views under the focus engine, which machine-guns
			// the tvOS focus/selection sounds ("static") while packets stream in.
			//
			// Clustering is off: every node gets its own pin. MapKit clusters on a
			// minimum on-screen separation of its own, not just on whether the views
			// overlap, so shrinking the view's frame only thinned the badges out — it
			// still merged nodes tens of metres apart, which on a wall display hides
			// exactly what you want to see. `displayPriority = .required` is what keeps
			// MapKit from decluttering the pins away now that it cannot merge them.
			// `ClusterCircleAnnotationView` is intentionally left in place so this is a
			// one-line revert if a dense mesh ever needs the badges back.
			clusteringIdentifier = nil
			displayPriority = .required
			updateContent()
		}
	}

	/// Cheap, idempotent refresh of the visual content. Safe to call on live updates.
	func updateContent() {
		guard let node = annotation as? NodeAnnotation else { return }
		// Several nodes on one coordinate: show the count, in the accent colour, the
		// way the old cluster badge did. This is the only case that still groups —
		// MapKit's own clustering is off, so nothing merges by proximity.
		let color: UIColor
		let text: String
		if node.memberCount > 1 {
			color = UIColor(named: "AccentColor") ?? .systemIndigo
			text = "\(node.memberCount)"
		} else {
			// Same node-color derivation as the iOS map pins.
			color = UIColor(hex: node.num)
			text = node.shortName.isEmpty ? String(format: "%04x", node.num & 0xffff) : node.shortName
		}
		if circle.backgroundColor != color { circle.backgroundColor = color }
		if label.text != text {
			label.text = text
			label.textColor = color.isLight() ? .black : .white
		}
	}

	// Invisible to the focus engine. Annotation views constantly appear/disappear
	// as clustering re-evaluates during zoom animations; when they're focusable,
	// every add/remove makes the focus engine re-evaluate — an audible click each
	// time, which reads as bursts of static on every list transition. The side
	// list is the selection path, so the pins don't need focus at all.
	override var canBecomeFocused: Bool { false }
}

/// Cluster badge matching the iOS `ClusterBadge`: accent circle + member count.
final class ClusterCircleAnnotationView: MKAnnotationView {
	static let reuseID = "clusterCircle"
	private static let diameter: CGFloat = 56

	private let circle = UIView()
	private let label = UILabel()

	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
		let d = Self.diameter
		frame = CGRect(x: 0, y: 0, width: d, height: d)
		collisionMode = .circle

		circle.frame = bounds
		circle.layer.cornerRadius = d / 2
		circle.layer.borderWidth = 3
		circle.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
		circle.backgroundColor = UIColor(named: "AccentColor") ?? .systemIndigo
		addSubview(circle)

		label.frame = bounds
		label.textAlignment = .center
		label.font = .systemFont(ofSize: 22, weight: .bold)
		label.textColor = .white
		label.adjustsFontSizeToFitWidth = true
		label.minimumScaleFactor = 0.5
		circle.addSubview(label)
	}

	required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override var annotation: MKAnnotation? {
		didSet {
			guard let cluster = annotation as? MKClusterAnnotation else { return }
			label.text = "\(cluster.memberAnnotations.count)"
			displayPriority = .required
		}
	}

	// Non-focusable, like the node pins. Making clusters focusable put focus targets
	// on the map, and because the map is a UIKit focus context while the side list is
	// SwiftUI @FocusState, focus got stuck on the map — the two systems don't hand off
	// cleanly, so returning to the list became a struggle. The list stays the single
	// selection path; selecting a node from it zooms down tight enough to break it out
	// of its cluster (see applySelection), which covers "see the node in a cluster".
	override var canBecomeFocused: Bool { false }
}

/// Marker annotation for the currently selected node. A standalone annotation —
/// NOT a decoration of the node's own pin — because MapKit freely hides node pins
/// when it absorbs them into clusters (view.hidden + collapse transform), which
/// made a ring drawn on the pin itself invisible in dense meshes. This annotation
/// never clusters, so the halo survives any cluster reshuffle.
/// `coordinate` is `@objc dynamic` so in-place moves are KVO-observed by MapKit
/// and animate the existing view.
final class SelectionHaloAnnotation: NSObject, MKAnnotation {
	@objc dynamic var coordinate: CLLocationCoordinate2D
	var num: UInt32
	var shortName: String
	init(coordinate: CLLocationCoordinate2D, num: UInt32, shortName: String) {
		self.coordinate = coordinate
		self.num = num
		self.shortName = shortName
	}
}

/// The selected-node marker: the node's own colored circle + short name at the
/// center of a pulsing halo ring. Self-contained on purpose — in a dense mesh
/// the node's regular pin is usually absorbed into a cluster badge (drawn at the
/// cluster centroid, not the node's position), so the halo must carry its own
/// marker rather than rely on the real pin showing underneath. Sits above
/// everything (`zPriority = .max`), never collides away (`displayPriority =
/// .required`), never clusters, and is inert to focus and hit-testing.
final class SelectionHaloView: MKAnnotationView {
	static let reuseID = "selectionHalo"
	private static let diameter: CGFloat = 116
	/// Same size as NodeCircleAnnotationView so the marker matches the other pins.
	private static let pinDiameter: CGFloat = 64

	private let ring = UIView()
	private let pin = UIView()
	private let label = UILabel()

	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
		let d = Self.diameter
		frame = CGRect(x: 0, y: 0, width: d, height: d)
		isEnabled = false                 // not selectable / hit-testable
		displayPriority = .required
		zPriority = .max

		ring.frame = bounds
		ring.layer.cornerRadius = d / 2
		ring.layer.borderWidth = 5
		ring.layer.borderColor = UIColor.white.cgColor
		ring.backgroundColor = UIColor.white.withAlphaComponent(0.15)
		ring.isUserInteractionEnabled = false
		addSubview(ring)

		// The node's own circle marker, centered in the ring — styled to match
		// NodeCircleAnnotationView so the selection reads as "that pin, haloed".
		let p = Self.pinDiameter
		pin.frame = CGRect(x: (d - p) / 2, y: (d - p) / 2, width: p, height: p)
		pin.layer.cornerRadius = p / 2
		pin.layer.borderWidth = 3
		pin.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
		pin.isUserInteractionEnabled = false
		addSubview(pin)

		label.frame = pin.bounds.insetBy(dx: 6, dy: 6)
		label.textAlignment = .center
		label.font = .systemFont(ofSize: 20, weight: .bold)
		label.adjustsFontSizeToFitWidth = true
		label.minimumScaleFactor = 0.4
		label.baselineAdjustment = .alignCenters
		pin.addSubview(label)
	}

	required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override var annotation: MKAnnotation? {
		didSet {
			// Re-assert on every reconfiguration — the node pins' didSet resets these
			// the same way, and that reset is exactly what broke the ring-on-pin design.
			clusteringIdentifier = nil
			displayPriority = .required
			zPriority = .max
			updateContent()
		}
	}

	/// Refresh the center marker from the annotation. Idempotent; called on
	/// (re)assignment and whenever the selection moves to a different node.
	func updateContent() {
		guard let halo = annotation as? SelectionHaloAnnotation else { return }
		let color = UIColor(hex: halo.num)
		let text = halo.shortName.isEmpty ? String(format: "%04x", halo.num & 0xffff) : halo.shortName
		if pin.backgroundColor != color {
			pin.backgroundColor = color
			label.textColor = color.isLight() ? .black : .white
		}
		if label.text != text { label.text = text }
	}

	/// Layer animations are stripped whenever the view leaves the window, so the
	/// pulse must be (re)attached on every return — not in init.
	override func didMoveToWindow() {
		super.didMoveToWindow()
		guard window != nil else { return }
		guard !UIAccessibility.isReduceMotionEnabled else { return }
		guard ring.layer.animation(forKey: "haloPulse") == nil else { return }
		let pulse = CABasicAnimation(keyPath: "transform.scale")
		pulse.fromValue = 1.0
		pulse.toValue = 1.12
		pulse.duration = 1.0
		pulse.autoreverses = true
		pulse.repeatCount = .infinity
		pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		ring.layer.add(pulse, forKey: "haloPulse")
	}

	override var canBecomeFocused: Bool { false }
}

struct MeshTVMapView: UIViewRepresentable {
	let nodes: [MeshNode]
	@Binding var selectedNodeNum: UInt32?
	/// Increment to re-frame the camera on the whole mesh (see MapScreen's button).
	var recenterToken: Int = 0
	/// Called on a Menu press while the map has focus. MKMapView captures the
	/// directional input for panning and never releases focus on its own, so
	/// without this the map is a focus trap (and an unhandled Menu press can
	/// suspend the app instead of going back). MapScreen uses it to hand focus
	/// back to the node list.
	var onMenuExit: (() -> Void)?

	/// Standard / Hybrid / Satellite, chosen in Settings. Shared via the same
	/// @AppStorage key so changing it there updates the map live.
	@AppStorage("tv.mapType") private var mapTypeRaw: Int = Int(MKMapType.standard.rawValue)
	private var mkMapType: MKMapType { MKMapType(rawValue: UInt(mapTypeRaw)) ?? .standard }

	/// Decoded offline basemap, or nil when no region has been downloaded. Owned by
	/// MapScreen so the decode survives view updates.
	var offlineVectors: OfflineVectorTileProvider?

	/// Drawn only over Standard — Hybrid and Satellite are imagery the vector basemap would hide.
	private var offlineBasemapVisible: Bool { mkMapType == .standard && offlineVectors != nil }

	func makeCoordinator() -> Coordinator { Coordinator(self) }

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator
		mapView.showsUserLocation = false          // no GPS on tvOS
		mapView.mapType = mkMapType
		// Pure display: the side list is the only interactive surface. Disabling user
		// interaction takes the map out of the tvOS focus engine entirely, so focus can
		// never jump from the list (or a pushed detail like Settings) onto the map — which
		// was leaving the user stranded on the map. The map still updates programmatically:
		// selection zoom, recenter, and annotation sync all keep working.
		mapView.isUserInteractionEnabled = false
		mapView.register(
			NodeCircleAnnotationView.self,
			forAnnotationViewWithReuseIdentifier: NodeCircleAnnotationView.reuseID
		)
		mapView.register(
			ClusterCircleAnnotationView.self,
			forAnnotationViewWithReuseIdentifier: ClusterCircleAnnotationView.reuseID
		)
		mapView.register(
			SelectionHaloView.self,
			forAnnotationViewWithReuseIdentifier: SelectionHaloView.reuseID
		)
		context.coordinator.applyInitialRegion(mapView, nodes: nodes)
		return mapView
	}

	func updateUIView(_ mapView: MKMapView, context: Context) {
		context.coordinator.parent = self
		if mapView.mapType != mkMapType { mapView.mapType = mkMapType }
		context.coordinator.sync(mapView, nodes: nodes)
		context.coordinator.applyInitialRegion(mapView, nodes: nodes)
		context.coordinator.applyRecenter(mapView, token: recenterToken, nodes: nodes)
		context.coordinator.applySelection(mapView, selectedNodeNum: selectedNodeNum)
		if let offlineVectors, offlineBasemapVisible {
			offlineVectors.updateIfNeeded()
			// tvOS renders against a dark interface, matching the iOS map's dark palette.
			context.coordinator.applyOfflineBasemap(mapView, provider: offlineVectors, dark: true)
		} else {
			context.coordinator.clearOfflineBasemap(mapView)
		}
	}

	// MARK: - Coordinator

	final class Coordinator: NSObject, MKMapViewDelegate {
		var parent: MeshTVMapView
		private var didSetInitialRegion = false
		/// Every located node number mapped to the pin that represents it.
		private var annotationsByNum: [UInt32: NodeAnnotation] = [:]
		/// One pin per distinct coordinate.
		private var annotationsByCoord: [CoordKey: NodeAnnotation] = [:]

		init(_ parent: MeshTVMapView) {
			self.parent = parent
		}

		@objc func menuPressed() {
			parent.onMenuExit?()
		}

		/// Diff the annotation set against `nodes` (add / update coordinate / remove),
		/// keyed by node number so we don't churn the whole map each update.
		func sync(_ mapView: MKMapView, nodes: [MeshNode]) {
			let located = nodes.filter { $0.hasLocation }

			// One pin per DISTINCT coordinate. Nodes reporting the exact same position
			// share a pin that shows their count; nothing else is ever merged, because
			// MapKit's own clustering is off (see `clusteringIdentifier`). This replaced
			// a ring-fan that pushed coincident nodes apart by 45m+ per member — with
			// clustering disabled that scattered a stacked group across whole blocks.
			var groups: [CoordKey: [MeshNode]] = [:]
			for node in located {
				guard let coordinate = node.coordinate else { continue }
				groups[CoordKey(coordinate), default: []].append(node)
			}

			// Drop pins whose coordinate no longer has anyone on it.
			for (key, annotation) in annotationsByCoord where groups[key] == nil {
				mapView.removeAnnotation(annotation)
				annotationsByCoord[key] = nil
				if let selectedNum, annotation.num == selectedNum || annotationOwner(of: selectedNum) === annotation {
					removeHalo(from: mapView)
					lastAppliedSelection = nil
				}
			}

			// Add or update the rest. Updates must be no-ops when nothing changed — this
			// runs on every published data tick, and any avoidable mutation here churns
			// MapKit and the focus engine.
			var numToAnnotation: [UInt32: NodeAnnotation] = [:]
			numToAnnotation.reserveCapacity(located.count)
			for (key, members) in groups {
				let sorted = members.sorted { $0.num < $1.num }
				guard let lead = sorted.first, let coordinate = lead.coordinate else { continue }
				let count = sorted.count

				let annotation: NodeAnnotation
				if let existing = annotationsByCoord[key] {
					annotation = existing
					if existing.num != lead.num {
						existing.num = lead.num
						existing.shortName = lead.shortName
						existing.subtitle = lead.shortName
						(mapView.view(for: existing) as? NodeCircleAnnotationView)?.updateContent()
					}
					if existing.memberCount != count {
						existing.memberCount = count
						(mapView.view(for: existing) as? NodeCircleAnnotationView)?.updateContent()
					}
					let title = count > 1
						? String(localized: "\(count) nodes here")
						: lead.displayName
					if existing.title != title { existing.title = title }
					if existing.shortName != lead.shortName, count == 1 {
						existing.subtitle = lead.shortName
						existing.shortName = lead.shortName
						(mapView.view(for: existing) as? NodeCircleAnnotationView)?.updateContent()
					}
				} else {
					annotation = NodeAnnotation(node: lead, coordinate: coordinate, memberCount: count)
					if count > 1 { annotation.title = String(localized: "\(count) nodes here") }
					annotationsByCoord[key] = annotation
					mapView.addAnnotation(annotation)
				}
				// Every member resolves to this pin, so selecting any of them from the
				// side list still finds a halo target.
				for member in sorted { numToAnnotation[member.num] = annotation }
			}
			annotationsByNum = numToAnnotation

			// Keep the halo glued to the selected node's pin as positions move.
			if let selectedNum, let annotation = annotationsByNum[selectedNum] {
				if let halo = haloAnnotation,
				   halo.coordinate.latitude != annotation.coordinate.latitude ||
					halo.coordinate.longitude != annotation.coordinate.longitude {
					halo.coordinate = annotation.coordinate
				}
			}
		}

		/// Exact-coordinate key. Nodes group only when both components match to the
		/// full 1e-7 degree precision the mesh reports (about 1 cm), i.e. genuinely the
		/// same reported position rather than merely nearby.
		struct CoordKey: Hashable {
			let lat: Int64
			let lon: Int64
			init(_ coordinate: CLLocationCoordinate2D) {
				lat = Int64((coordinate.latitude * 1e7).rounded())
				lon = Int64((coordinate.longitude * 1e7).rounded())
			}
		}

		/// The pin currently standing in for `num`, if any.
		private func annotationOwner(of num: UInt32?) -> NodeAnnotation? {
			guard let num else { return nil }
			return annotationsByNum[num]
		}

		/// Frame the located nodes once, when we first have something to show.
		/// No device GPS, so we center on the centroid of reported positions.
		func applyInitialRegion(_ mapView: MKMapView, nodes: [MeshNode]) {
			guard !didSetInitialRegion else { return }
			guard frameAllNodes(mapView, nodes: nodes, animated: false) else { return }
			didSetInitialRegion = true
		}

		/// Re-frame on the whole mesh when the user asks (recenter button).
		func applyRecenter(_ mapView: MKMapView, token: Int, nodes: [MeshNode]) {
			guard token != lastRecenterToken else { return }
			lastRecenterToken = token
			guard token > 0 else { return }   // 0 is the initial value, not a request
			mapView.deselectAnnotation(mapView.selectedAnnotations.first, animated: false)
			_ = frameAllNodes(mapView, nodes: nodes, animated: true)
		}
		private var lastRecenterToken = 0

		/// Set a region, but CUT instead of flying when the jump is big. A long
		/// animated flight re-evaluates clustering every frame (pins/clusters
		/// popping) while tiles stream in behind — which reads as visual static.
		/// Short hops still animate; anything past city-to-city just cuts.
		private func setRegionSmart(_ mapView: MKMapView, target: MKCoordinateRegion) {
			let meters = MKMapPoint(mapView.centerCoordinate)
				.distance(to: MKMapPoint(target.center))
			let spanRatio = mapView.region.span.latitudeDelta
				/ max(target.span.latitudeDelta, 0.0001)
			let bigJump = meters > 80_000 || spanRatio > 4 || spanRatio < 0.25
			mapView.setRegion(target, animated: !bigJump)
		}

		/// Fit the camera to every located node's reported position.
		@discardableResult
		private func frameAllNodes(_ mapView: MKMapView, nodes: [MeshNode], animated: Bool) -> Bool {
			let coords = nodes.compactMap { $0.coordinate }
			guard !coords.isEmpty else { return false }

			let lats = coords.map(\.latitude)
			let lons = coords.map(\.longitude)
			let minLat = lats.min()!, maxLat = lats.max()!
			let minLon = lons.min()!, maxLon = lons.max()!
			let center = CLLocationCoordinate2D(
				latitude: (minLat + maxLat) / 2,
				longitude: (minLon + maxLon) / 2
			)
			let span = MKCoordinateSpan(
				latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
				longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
			)
			let region = MKCoordinateRegion(center: center, span: span)
			if animated {
				setRegionSmart(mapView, target: region)   // cuts when the jump is big
			} else {
				mapView.setRegion(region, animated: false)
			}
			return true
		}

		/// The node number currently selected from the side list, or nil. `sync`
		/// reads it to keep the halo tracking a moving selected node.
		private(set) var selectedNum: UInt32?
		/// The single halo annotation marking the selection (nil = none shown).
		private var haloAnnotation: SelectionHaloAnnotation?

		/// Show the halo on `node`, moving the existing one when present so MapKit
		/// animates it instead of blinking remove/add. Exactly one halo ever exists
		/// (rapid re-selection reuses it); the center marker re-renders for the new
		/// node's color + short name.
		private func showHalo(on node: NodeAnnotation, mapView: MKMapView) {
			if let halo = haloAnnotation {
				halo.num = node.num
				halo.shortName = node.shortName
				if halo.coordinate.latitude != node.coordinate.latitude ||
					halo.coordinate.longitude != node.coordinate.longitude {
					halo.coordinate = node.coordinate   // @objc dynamic → KVO → animated move
				}
				(mapView.view(for: halo) as? SelectionHaloView)?.updateContent()
			} else {
				let halo = SelectionHaloAnnotation(
					coordinate: node.coordinate, num: node.num, shortName: node.shortName
				)
				haloAnnotation = halo
				mapView.addAnnotation(halo)
			}
		}

		private func removeHalo(from mapView: MKMapView) {
			guard let halo = haloAnnotation else { return }
			mapView.removeAnnotation(halo)
			haloAnnotation = nil
		}

		func applySelection(_ mapView: MKMapView, selectedNodeNum: UInt32?) {
			guard let num = selectedNodeNum else {
				selectedNum = nil
				lastAppliedSelection = nil
				pendingSelectionFly?.cancel()
				pendingSelectionNum = nil
				removeHalo(from: mapView)
				return
			}
			guard num != lastAppliedSelection, num != pendingSelectionNum else { return }

			pendingSelectionFly?.cancel()
			pendingSelectionNum = nil

			// Selected a node with no annotation yet (no location). Remember the
			// selection but hide any stale halo; when the node's position arrives,
			// updateUIView re-runs applySelection (lastAppliedSelection is unset) and
			// the halo appears then.
			guard let annotation = annotationsByNum[num] else {
				selectedNum = num
				removeHalo(from: mapView)
				return
			}

			selectedNum = num
			// The halo is its own never-clustering annotation carrying its own copy of
			// the node marker — the node's real pin is usually hidden inside a cluster
			// badge in a dense mesh, so the halo renders the marker itself.
			showHalo(on: annotation, mapView: mapView)

			// Debounce the camera fly so gliding across rows doesn't launch
			// overlapping cross-country animations.
			pendingSelectionNum = num
			let fly = DispatchWorkItem { [weak self, weak mapView] in
				guard let self, let mapView else { return }
				guard let annotation = self.annotationsByNum[num] else {
					self.pendingSelectionNum = nil
					return
				}
				let tight = MKCoordinateRegion(
					center: annotation.coordinate,
					latitudinalMeters: Self.selectionZoomMeters,
					longitudinalMeters: Self.selectionZoomMeters
				)
				let target = mapView.region.span.latitudeDelta > tight.span.latitudeDelta
					? tight
					: MKCoordinateRegion(center: annotation.coordinate, span: mapView.region.span)
				mapView.setRegion(target, animated: true)
				self.lastAppliedSelection = num
				self.pendingSelectionNum = nil
			}
			pendingSelectionFly = fly
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: fly)
		}

		/// Tight enough to split the coincident-stack fan ring (~45-65 m radius)
		/// into individual pins in the dense sim, so the selected node is visible
		/// as its own pin — not swallowed by a cluster badge — after the fly lands.
		private static let selectionZoomMeters: CLLocationDistance = 400
		private var lastAppliedSelection: UInt32?
		private var pendingSelectionNum: UInt32?
		private var pendingSelectionFly: DispatchWorkItem?

		// MARK: MKMapViewDelegate

		func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
			// Halo first — it must never fall into the node/cluster branches.
			if annotation is SelectionHaloAnnotation {
				return mapView.dequeueReusableAnnotationView(
					withIdentifier: SelectionHaloView.reuseID,
					for: annotation
				)
			}
			if annotation is MKClusterAnnotation {
				return mapView.dequeueReusableAnnotationView(
					withIdentifier: ClusterCircleAnnotationView.reuseID,
					for: annotation
				)
			}
			guard annotation is NodeAnnotation else { return nil }
			let view = mapView.dequeueReusableAnnotationView(
				withIdentifier: NodeCircleAnnotationView.reuseID,
				for: annotation
			)
			(view as? NodeCircleAnnotationView)?.updateContent()
			return view
		}

		func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
			guard let style = offlineStyles[ObjectIdentifier(overlay)] else {
				return MKOverlayRenderer(overlay: overlay)
			}
			switch overlay {
			case let polygon as MKPolygon:
				let renderer = MKPolygonRenderer(polygon: polygon)
				renderer.fillColor = style.fill
				renderer.lineWidth = 0
				return renderer
			case let multi as MKMultiPolygon:
				let renderer = MKMultiPolygonRenderer(multiPolygon: multi)
				renderer.fillColor = style.fill
				renderer.lineWidth = 0
				return renderer
			case let multi as MKMultiPolyline:
				let renderer = MKMultiPolylineRenderer(multiPolyline: multi)
				renderer.strokeColor = style.stroke
				renderer.lineWidth = style.lineWidth
				renderer.lineCap = .round
				renderer.lineJoin = .round
				return renderer
			default:
				return MKOverlayRenderer(overlay: overlay)
			}
		}

		// MARK: Offline basemap

		/// Style for each offline overlay, keyed by object identity — MapKit hands the renderer
		/// callback an overlay, not our model, so this is the lookup back to how it should draw.
		struct OfflineOverlayStyle {
			var fill: UIColor?
			var stroke: UIColor?
			var lineWidth: CGFloat
		}

		private var offlineStyles: [ObjectIdentifier: OfflineOverlayStyle] = [:]
		private var offlineOverlays: [MKOverlay] = []
		private var lastOfflineRevision = -1

		/// Rebuilds the offline basemap overlays from the provider's latest decode. Mirrors the
		/// iOS map's layering: an earth fill per coverage box, then parks/water, then roads drawn
		/// casing-first so the centrelines read as outlined roads.
		func applyOfflineBasemap(_ mapView: MKMapView, provider: OfflineVectorTileProvider, dark: Bool) {
			guard provider.revision != lastOfflineRevision else { return }
			lastOfflineRevision = provider.revision

			if !offlineOverlays.isEmpty {
				mapView.removeOverlays(offlineOverlays)
				offlineOverlays = []
				offlineStyles = [:]
			}
			guard provider.isAvailable, !provider.coverageAreas.isEmpty else { return }

			var added: [MKOverlay] = []
			func add(_ overlay: MKOverlay, _ style: OfflineOverlayStyle) {
				offlineStyles[ObjectIdentifier(overlay)] = style
				added.append(overlay)
			}

			// Earth fill per coverage box, so uncovered gaps read as land rather than Apple's basemap.
			for bounds in provider.coverageAreas {
				var corners = [
					CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon),
					CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.maxLon),
					CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon),
					CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.minLon)
				]
				add(MKPolygon(coordinates: &corners, count: corners.count),
					OfflineOverlayStyle(fill: OfflineMapPalette.earth(dark: dark), stroke: nil, lineWidth: 0))
			}

			// Fills, batched per role (parks under water).
			let fillsByRole = Dictionary(grouping: provider.polygons, by: { $0.role })
			for role in [OfflineFeatureRole.park, .green, .water] {
				guard let polys = fillsByRole[role], let fill = OfflineMapPalette.fill(role, dark: dark) else { continue }
				let shapes = polys.compactMap { poly -> MKPolygon? in
					guard poly.coordinates.count >= 3 else { return nil }
					var coords = poly.coordinates
					return MKPolygon(coordinates: &coords, count: coords.count)
				}
				guard !shapes.isEmpty else { continue }
				add(MKMultiPolygon(shapes), OfflineOverlayStyle(fill: fill, stroke: nil, lineWidth: 0))
			}

			// Roads, batched per role so the whole grid is a handful of overlays.
			let roadsByRole = Dictionary(grouping: provider.roads, by: { $0.role })
			func multiPolyline(_ role: OfflineFeatureRole) -> MKMultiPolyline? {
				guard let lines = roadsByRole[role] else { return nil }
				let shapes = lines.compactMap { line -> MKPolyline? in
					guard line.coordinates.count >= 2 else { return nil }
					var coords = line.coordinates
					return MKPolyline(coordinates: &coords, count: coords.count)
				}
				return shapes.isEmpty ? nil : MKMultiPolyline(shapes)
			}
			let roadClasses: [OfflineFeatureRole] = [.minorRoad, .mediumRoad, .majorRoad]
			for role in roadClasses {
				guard let casing = OfflineMapPalette.roadCasing(role, dark: dark), let multi = multiPolyline(role) else { continue }
				add(multi, OfflineOverlayStyle(fill: nil, stroke: casing, lineWidth: OfflineMapPalette.roadCasingWidth(role)))
			}
			for role in roadClasses {
				guard let fill = OfflineMapPalette.roadFill(role, dark: dark), let multi = multiPolyline(role) else { continue }
				add(multi, OfflineOverlayStyle(fill: nil, stroke: fill, lineWidth: OfflineMapPalette.roadWidth(role)))
			}
			for role in [OfflineFeatureRole.rail, .boundary] {
				guard let color = OfflineMapPalette.line(role, dark: dark), let multi = multiPolyline(role) else { continue }
				add(multi, OfflineOverlayStyle(fill: nil, stroke: color, lineWidth: 1))
			}

			guard !added.isEmpty else { return }
			mapView.addOverlays(added, level: .aboveRoads)
			offlineOverlays = added
		}

		/// Drops the offline overlays (region deleted, or the user switched to Hybrid/Satellite).
		func clearOfflineBasemap(_ mapView: MKMapView) {
			guard !offlineOverlays.isEmpty else { return }
			mapView.removeOverlays(offlineOverlays)
			offlineOverlays = []
			offlineStyles = [:]
			lastOfflineRevision = -1
		}

	}
}
