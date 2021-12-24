//
//  PositionAnnotationView.swift
//  MeshtasticClient
//
//  Created by Joshua Pirihi on 24/12/21.
//

import UIKit
import MapKit

class PositionAnnotation: NSObject, MKAnnotation {
	
	// This property must be key-value observable, which the `@objc dynamic` attributes provide.
	@objc dynamic var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
	
	// Required if you set the annotation view's `canShowCallout` property to `true`
	var title: String? = "Title"
	
	var shortName: String?
	
	// This property defined by `MKAnnotation` is not required.
	//var subtitle: String? = NSLocalizedString("SAN_FRANCISCO_SUBTITLE", comment: "SF annotation")
}

class PositionAnnotationView: MKAnnotationView {

	private let annotationFrame = CGRect(x: 0, y: 0, width: 32, height: 32)
		private let label: UILabel

		override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
			self.label = UILabel(frame: annotationFrame.offsetBy(dx: 0, dy: 0))
			super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
			self.frame = annotationFrame
			self.label.font = UIFont.preferredFont(forTextStyle: .caption2)
			self.label.textColor = .white
			self.label.textAlignment = .center
			self.backgroundColor = .clear
			self.addSubview(label)
		}

		required init?(coder aDecoder: NSCoder) {
			fatalError("init(coder:) not implemented!")
		}

		public var name: String = "" {
			didSet {
				self.label.text = name
			}
		}

		override func draw(_ rect: CGRect) {
			guard let context = UIGraphicsGetCurrentContext() else { return }

			let circleRect = CGRect(x: 1, y: 1, width: 30, height: 30)

			context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1.0, alpha: 1.0))
			
			context.fillEllipse(in: circleRect)

		}


}
