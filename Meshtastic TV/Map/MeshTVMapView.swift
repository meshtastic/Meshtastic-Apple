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
		didSet { configure() }
	}

	func configure() {
		guard let node = annotation as? NodeAnnotation else { return }
		// Same node-color derivation as the iOS map pins.
		let color = UIColor(hex: node.num)
		circle.backgroundColor = color
		label.text = node.shortName.isEmpty ? String(format: "%04x", node.num & 0xffff) : node.shortName
		label.textColor = color.isLight() ? .black : .white
		clusteringIdentifier = "meshNode"
		displayPriority = .required
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

			// Add or update the rest.
			for node in located {
				guard let coordinate = node.coordinate else { continue }
				if let existing = annotationsByNum[node.num] {
					if existing.coordinate.latitude != coordinate.latitude ||
						existing.coordinate.longitude != coordinate.longitude {
						existing.coordinate = coordinate
					}
					existing.title = node.displayName
					existing.subtitle = node.shortName
					existing.shortName = node.shortName
					(mapView.view(for: existing) as? NodeCircleAnnotationView)?.configure()
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
			let coords = nodes.compactMap { $0.coordinate }
			guard !coords.isEmpty else { return }
			didSetInitialRegion = true

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
			mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
		}

		/// Center on and select the annotation chosen from the side list.
		func applySelection(_ mapView: MKMapView, selectedNodeNum: UInt32?) {
			guard let num = selectedNodeNum, let annotation = annotationsByNum[num] else { return }
			if mapView.selectedAnnotations.first as? NodeAnnotation !== annotation {
				mapView.setCenter(annotation.coordinate, animated: true)
				mapView.selectAnnotation(annotation, animated: true)
			}
		}

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
			(view as? NodeCircleAnnotationView)?.configure()
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
