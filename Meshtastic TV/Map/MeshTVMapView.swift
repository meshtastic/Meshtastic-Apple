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
	let num: UInt32
	dynamic var coordinate: CLLocationCoordinate2D
	var title: String?
	var subtitle: String?
	var shortName: String

	init(node: MeshNode, coordinate: CLLocationCoordinate2D) {
		self.num = node.num
		self.coordinate = coordinate
		self.title = node.displayName
		self.subtitle = node.shortName
		self.shortName = node.shortName
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
			clusteringIdentifier = "meshNode"
			displayPriority = .required
			updateContent()
		}
	}

	/// Cheap, idempotent refresh of the visual content. Safe to call on live updates.
	func updateContent() {
		guard let node = annotation as? NodeAnnotation else { return }
		// Same node-color derivation as the iOS map pins.
		let color = UIColor(hex: node.num)
		let text = node.shortName.isEmpty ? String(format: "%04x", node.num & 0xffff) : node.shortName
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
		private var annotationsByNum: [UInt32: NodeAnnotation] = [:]
		private var lastSpreadKey: [Int64] = []
		private var cachedOverrides: [UInt32: CLLocationCoordinate2D] = [:]

		init(_ parent: MeshTVMapView) {
			self.parent = parent
		}

		/// Diff the annotation set against `nodes` (add / update coordinate / remove),
		/// keyed by node number so we don't churn the whole map each update.
		func sync(_ mapView: MKMapView, nodes: [MeshNode]) {
			let located = nodes.filter { $0.hasLocation }
			// Recompute when a node identity or quantized position changes.
			let spreadKey = Self.spreadKey(located)
			if spreadKey != lastSpreadKey {
				cachedOverrides = spreadOverrides(located)
				lastSpreadKey = spreadKey
			}
			let overrides = cachedOverrides
			let incoming = Set(located.map { $0.num })

			// Remove annotations for nodes that are gone.
			for (num, annotation) in annotationsByNum where !incoming.contains(num) {
				mapView.removeAnnotation(annotation)
				annotationsByNum[num] = nil
				if num == selectedNum {
					removeHalo(from: mapView)
					lastAppliedSelection = nil
				}
			}

			// Add or update the rest. Updates must be no-ops when nothing changed —
			// this runs on every published data tick, and any avoidable mutation here
			// (retitling, reconfiguring views) churns MapKit + the focus engine.
			for node in located {
				guard let real = node.coordinate else { continue }
				// Fan (near-)coincident nodes onto a small ring so a stacked cluster still
				// separates into individual pins once you zoom in — nodes at the same
				// coordinate otherwise never split no matter how far you zoom.
				let coordinate = overrides[node.num] ?? real
				if let existing = annotationsByNum[node.num] {
					if existing.coordinate.latitude != coordinate.latitude ||
						existing.coordinate.longitude != coordinate.longitude {
						existing.coordinate = coordinate
						// Keep the selection halo glued to a moving selected node.
						if node.num == selectedNum { haloAnnotation?.coordinate = coordinate }
					}
					if existing.title != node.displayName { existing.title = node.displayName }
					if existing.shortName != node.shortName {
						existing.subtitle = node.shortName
						existing.shortName = node.shortName
						(mapView.view(for: existing) as? NodeCircleAnnotationView)?.updateContent()
						// The halo carries its own copy of the marker — refresh it too.
						if node.num == selectedNum, let halo = haloAnnotation {
							halo.shortName = node.shortName
							(mapView.view(for: halo) as? SelectionHaloView)?.updateContent()
						}
					}
				} else {
					let annotation = NodeAnnotation(node: node, coordinate: coordinate)
					annotationsByNum[node.num] = annotation
					mapView.addAnnotation(annotation)
				}
			}
		}

		/// Identity and ~1 m position of every located node in stable order.
		private static func spreadKey(_ nodes: [MeshNode]) -> [Int64] {
			nodes.compactMap { node -> (UInt32, Int64, Int64)? in
				guard let coordinate = node.coordinate else { return nil }
				return (
					node.num,
					Int64((coordinate.latitude * 1e5).rounded()),
					Int64((coordinate.longitude * 1e5).rounded())
				)
			}
			.sorted { $0.0 < $1.0 }
			.flatMap { [Int64($0.0), $0.1, $0.2] }
		}

		/// Fan out nodes on (nearly) the same coordinate into a small ring, so a stacked
		/// cluster breaks into individual pins once zoomed in — coincident nodes otherwise
		/// never split no matter how far you zoom. Ported from the iOS map's behaviour from
		/// before the coincident-disambiguation sheet; the ring is larger here because the
		/// TV's node circles are big and need more separation to un-cluster.
		private func spreadOverrides(_ nodes: [MeshNode]) -> [UInt32: CLLocationCoordinate2D] {
			var groups: [Int64: [MeshNode]] = [:]
			for node in nodes {
				guard let c = node.coordinate else { continue }
				// Quantize to ~1 m so only (near-)coincident nodes group together.
				let latKey = Int64((c.latitude * 1e5).rounded())
				let lonKey = Int64((c.longitude * 1e5).rounded())
				groups[latKey &* 100_000_000 &+ lonKey, default: []].append(node)
			}
			var overrides: [UInt32: CLLocationCoordinate2D] = [:]
			let metersPerDegLat = 111_320.0
			for members in groups.values where members.count > 1 {
				let sorted = members.sorted { $0.num < $1.num }
				guard let base = sorted.first?.coordinate else { continue }
				let metersPerDegLon = max(1.0, metersPerDegLat * cos(base.latitude * .pi / 180))
				// Grow the ring with crowd size so even a big pile stays individually visible.
				let radius = 45.0 + Double(sorted.count) * 4.0
				for (index, member) in sorted.enumerated() {
					let angle = 2 * Double.pi * Double(index) / Double(sorted.count)
					overrides[member.num] = CLLocationCoordinate2D(
						latitude: base.latitude + (radius * sin(angle)) / metersPerDegLat,
						longitude: base.longitude + (radius * cos(angle)) / metersPerDegLon
					)
				}
			}
			return overrides
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

		/// Fit the camera to every located node's reported position, inside the part
		/// of the map the user can actually see.
		///
		/// The map is full-bleed, so the side list covers its left edge. Fitting the
		/// mesh to the whole view therefore parked a slice of it behind the list and
		/// zoomed out further than needed to compensate. `setVisibleMapRect` with edge
		/// padding fits the visible area instead, and does the padding job the old
		/// 1.4x span multiplier was doing by hand.
		@discardableResult
		private func frameAllNodes(_ mapView: MKMapView, nodes: [MeshNode], animated: Bool) -> Bool {
			let coords = nodes.compactMap { $0.coordinate }
			guard !coords.isEmpty else { return false }

			// Fit where the mesh actually IS, not its extremes. A handful of nodes
			// parked across town — someone who drove home, a stale position — stretched
			// the bounding box far past the event and forced the camera way out. Trim to
			// the middle 90% on each axis so stragglers don't dominate the framing; they
			// stay on the map, just outside the initial frame.
			let rect = boundingRect(of: coords, trimming: 0.05)
			guard !rect.isNull else { return false }

			// A single node (or several on one spot) gives a zero-size rect, which
			// setVisibleMapRect cannot fit. Give it a small neighbourhood instead.
			if rect.size.width < 1, rect.size.height < 1 {
				let region = MKCoordinateRegion(
					center: coords[0],
					span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
				)
				mapView.setRegion(region, animated: animated)
				return true
			}

			// How much of the map's left edge the side list hides. Measured rather than
			// assumed, so it stays right if the layout changes.
			let originInWindow = mapView.convert(CGPoint.zero, to: nil).x
			let hiddenLeft = max(0, TVTheme.sideListWidth - originInWindow)
			let margin: CGFloat = 40
			let padding = UIEdgeInsets(
				top: margin,
				left: hiddenLeft + margin,
				bottom: margin,
				right: margin
			)

			if animated, isBigJump(mapView, target: rect) {
				// Long flights re-evaluate clustering every frame while tiles stream in,
				// which reads as visual static — cut instead (same rule as setRegionSmart).
				mapView.setVisibleMapRect(rect, edgePadding: padding, animated: false)
			} else {
				mapView.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
			}
			return true
		}


		/// Bounding rect of `coords` after dropping the outermost `fraction` of values
		/// on each axis (per axis independently, so one distant node cannot widen both).
		/// `fraction` of 0 gives the full extent.
		private func boundingRect(of coords: [CLLocationCoordinate2D], trimming fraction: Double) -> MKMapRect {
			guard !coords.isEmpty else { return .null }
			let points = coords.map(MKMapPoint.init)
			let xs = points.map(\.x).sorted()
			let ys = points.map(\.y).sorted()
			// Keep at least a handful of points so a small mesh is never trimmed away.
			let drop = min(Int(Double(points.count) * fraction), max(0, (points.count - 4) / 2))
			let loX = xs[drop], hiX = xs[xs.count - 1 - drop]
			let loY = ys[drop], hiY = ys[ys.count - 1 - drop]
			return MKMapRect(x: loX, y: loY, width: hiX - loX, height: hiY - loY)
		}

		/// Distance/scale test shared with `setRegionSmart`, in map-rect terms.
		private func isBigJump(_ mapView: MKMapView, target rect: MKMapRect) -> Bool {
			let targetCenter = MKMapPoint(x: rect.midX, y: rect.midY)
			let meters = MKMapPoint(mapView.centerCoordinate).distance(to: targetCenter)
			let currentWidth = mapView.visibleMapRect.size.width
			let ratio = currentWidth / max(rect.size.width, 1)
			return meters > 80_000 || ratio > 4 || ratio < 0.25
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
