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

	// Grow when focused so the Siri Remote highlight is obvious from the couch.
	override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
		super.didUpdateFocus(in: context, with: coordinator)
		coordinator.addCoordinatedAnimations({
			self.transform = self.isFocused ? CGAffineTransform(scaleX: 1.35, y: 1.35) : .identity
		})
	}
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
}

struct MeshTVMapView: UIViewRepresentable {
	let nodes: [MeshNode]
	@Binding var selectedNodeNum: UInt32?
	/// Increment to re-frame the camera on the whole mesh (see MapScreen's button).
	var recenterToken: Int = 0

	func makeCoordinator() -> Coordinator { Coordinator(self) }

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator
		mapView.showsUserLocation = false          // no GPS on tvOS
		mapView.mapType = .standard
		mapView.register(
			NodeCircleAnnotationView.self,
			forAnnotationViewWithReuseIdentifier: NodeCircleAnnotationView.reuseID
		)
		mapView.register(
			ClusterCircleAnnotationView.self,
			forAnnotationViewWithReuseIdentifier: ClusterCircleAnnotationView.reuseID
		)
		context.coordinator.applyInitialRegion(mapView, nodes: nodes)
		return mapView
	}

	func updateUIView(_ mapView: MKMapView, context: Context) {
		context.coordinator.parent = self
		context.coordinator.sync(mapView, nodes: nodes)
		context.coordinator.applyInitialRegion(mapView, nodes: nodes)
		context.coordinator.applyRecenter(mapView, token: recenterToken, nodes: nodes)
		context.coordinator.applySelection(mapView, selectedNodeNum: selectedNodeNum)
	}

	// MARK: - Coordinator

	final class Coordinator: NSObject, MKMapViewDelegate {
		var parent: MeshTVMapView
		private var didSetInitialRegion = false
		private var annotationsByNum: [UInt32: NodeAnnotation] = [:]

		init(_ parent: MeshTVMapView) {
			self.parent = parent
		}

		/// Diff the annotation set against `nodes` (add / update coordinate / remove),
		/// keyed by node number so we don't churn the whole map each update.
		func sync(_ mapView: MKMapView, nodes: [MeshNode]) {
			let located = nodes.filter { $0.hasLocation }
			let incoming = Set(located.map { $0.num })

			// Remove annotations for nodes that are gone.
			for (num, annotation) in annotationsByNum where !incoming.contains(num) {
				mapView.removeAnnotation(annotation)
				annotationsByNum[num] = nil
			}

			// Add or update the rest. Updates must be no-ops when nothing changed —
			// this runs on every published data tick, and any avoidable mutation here
			// (retitling, reconfiguring views) churns MapKit + the focus engine.
			for node in located {
				guard let coordinate = node.coordinate else { continue }
				if let existing = annotationsByNum[node.num] {
					if existing.coordinate.latitude != coordinate.latitude ||
						existing.coordinate.longitude != coordinate.longitude {
						existing.coordinate = coordinate
					}
					if existing.title != node.displayName { existing.title = node.displayName }
					if existing.shortName != node.shortName {
						existing.subtitle = node.shortName
						existing.shortName = node.shortName
						(mapView.view(for: existing) as? NodeCircleAnnotationView)?.updateContent()
					}
				} else {
					let annotation = NodeAnnotation(node: node, coordinate: coordinate)
					annotationsByNum[node.num] = annotation
					mapView.addAnnotation(annotation)
				}
			}
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
			mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: animated)
			return true
		}

		/// Center on the node chosen from the side list. Center-only, and only when
		/// the selection actually changed: tvOS `List(selection:)` follows *focus*,
		/// so this fires for every row the user glides across — animated
		/// `selectAnnotation` here popped a callout (with its selection sound) per
		/// row, which read as bursts of static while browsing the list.
		func applySelection(_ mapView: MKMapView, selectedNodeNum: UInt32?) {
			guard let num = selectedNodeNum else {
				lastAppliedSelection = nil   // re-selecting the same node later must still center
				return
			}
			guard num != lastAppliedSelection else { return }
			lastAppliedSelection = num
			guard let annotation = annotationsByNum[num] else { return }
			mapView.setCenter(annotation.coordinate, animated: true)
		}
		private var lastAppliedSelection: UInt32?

		// MARK: MKMapViewDelegate

		func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
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

		func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
			if let node = view.annotation as? NodeAnnotation {
				parent.selectedNodeNum = node.num
			} else if let cluster = view.annotation as? MKClusterAnnotation {
				// Zoom into a cluster rather than selecting it.
				mapView.setRegion(
					MKCoordinateRegion(
						center: cluster.coordinate,
						span: MKCoordinateSpan(
							latitudeDelta: mapView.region.span.latitudeDelta / 3,
							longitudeDelta: mapView.region.span.longitudeDelta / 3
						)
					),
					animated: true
				)
			}
		}
	}
}
