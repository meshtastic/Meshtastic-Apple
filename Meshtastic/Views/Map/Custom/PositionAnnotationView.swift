////
////  PositionAnnotationView.swift
////  MeshtasticApple
////
////  Created by Joshua Pirihi on 24/12/21.
////
//
//import UIKit
//import MapKit
//import SwiftUI
//
//// a simple circle annotation, with a string in it
//class PositionAnnotation: NSObject, MKAnnotation {
//
//	// This property must be key-value observable, which the `@objc dynamic` attributes provide.
//	@objc dynamic var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
//
//	// Required if you set the annotation view's `canShowCallout` property to `true`
//	// this string fills the callout label when you tap an annotation
//	var title: String?
//
//	// the text to appear inside the little circle
//	var shortName: String?
//
//}
//
//class PositionAnnotationView: MKAnnotationView {
//
//	private let annotationFrame = CGRect(x: 0, y: 0, width: 40, height: 40)
//	private let label: UILabel
//
//	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
//		self.label = UILabel(frame: annotationFrame.offsetBy(dx: 0, dy: 0))
//		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
//		self.frame = annotationFrame
//		self.label.font = UIFont.preferredFont(forTextStyle: .caption2)
//		self.label.textColor = .white
//		self.label.textAlignment = .center
//		self.backgroundColor = .clear
//		self.addSubview(label)
//	}
//
//	required init?(coder aDecoder: NSCoder) {
//		fatalError("init(coder:) not implemented!")
//	}
//
//	public var name: String = "" {
//		didSet {
//			self.label.text = name
//		}
//	}
//
//	override func draw(_ rect: CGRect) {
//		guard let context = UIGraphicsGetCurrentContext() else { return }
//
//		let circleRect = CGRect(x: 1, y: 1, width: 38, height: 38)
//		context.setFillColor(Color.accentColor.cgColor ?? CGColor(red: 0, green: 0.5, blue: 1.0, alpha: 1.0))
//		context.fillEllipse(in: circleRect)
//	}
//}
