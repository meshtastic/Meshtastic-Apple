//
//  MessageBubbleView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 11/24/26.
//
//  Speech bubble above a node's pin showing the message it just sent. Its own
//  annotation, like the selection halo, so it never groups with the node pins.
//

import MapKit
import UIKit

final class MessageBubbleAnnotation: NSObject, MKAnnotation {
	let message: MapMessage
	var coordinate: CLLocationCoordinate2D { message.coordinate }

	init(message: MapMessage) {
		self.message = message
	}
}

final class MessageBubbleView: MKAnnotationView {
	static let reuseID = "messageBubble"
	private static let maxTextWidth: CGFloat = 560
	private static let padding: CGFloat = 24
	private static let tailHeight: CGFloat = 22
	private static let tailWidth: CGFloat = 36
	/// Gap between the tail's tip and the center of the node pin, so the tip
	/// touches the top of the pin (NodeCircleAnnotationView is 64 across).
	private static let pinRadius: CGFloat = 32

	private let bubble = UIView()
	private let tail = CAShapeLayer()
	private let senderLabel = UILabel()
	private let textLabel = UILabel()

	override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
		super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
		isEnabled = false
		collisionMode = .none

		bubble.backgroundColor = UIColor(white: 0.1, alpha: 0.92)
		bubble.layer.cornerRadius = 20
		bubble.layer.cornerCurve = .continuous
		bubble.layer.borderWidth = 4
		addSubview(bubble)
		tail.fillColor = UIColor(white: 0.1, alpha: 0.92).cgColor
		layer.addSublayer(tail)

		senderLabel.font = .systemFont(ofSize: 24, weight: .semibold)
		senderLabel.textColor = UIColor.white.withAlphaComponent(0.75)
		senderLabel.numberOfLines = 1
		senderLabel.adjustsFontSizeToFitWidth = true
		senderLabel.minimumScaleFactor = 0.6
		bubble.addSubview(senderLabel)

		textLabel.font = .systemFont(ofSize: 32, weight: .regular)
		textLabel.textColor = .white
		textLabel.numberOfLines = 0
		bubble.addSubview(textLabel)
	}

	required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override var annotation: MKAnnotation? {
		didSet {
			clusteringIdentifier = nil
			displayPriority = .required
			zPriority = .max
			updateContent()
		}
	}

	private func updateContent() {
		guard let message = (annotation as? MessageBubbleAnnotation)?.message else { return }
		let color = UIColor(hex: message.num)
		bubble.layer.borderColor = color.cgColor
		senderLabel.text = message.senderName
		textLabel.text = message.text

		let pad = Self.padding
		let fit = CGSize(width: Self.maxTextWidth, height: .greatestFiniteMagnitude)
		let textSize = textLabel.sizeThatFits(fit)
		let senderSize = senderLabel.sizeThatFits(fit)
		let contentWidth = min(Self.maxTextWidth, max(textSize.width, senderSize.width))
		let spacing: CGFloat = 8

		senderLabel.frame = CGRect(x: pad, y: pad, width: contentWidth, height: senderSize.height)
		textLabel.frame = CGRect(
			x: pad,
			y: senderLabel.frame.maxY + spacing,
			width: contentWidth,
			height: textSize.height
		)
		let bubbleSize = CGSize(width: contentWidth + pad * 2, height: textLabel.frame.maxY + pad)
		bubble.frame = CGRect(origin: .zero, size: bubbleSize)

		// Tail centered under the bubble, its tip at the bottom of the view.
		let path = UIBezierPath()
		let midX = bubbleSize.width / 2
		path.move(to: CGPoint(x: midX - Self.tailWidth / 2, y: bubbleSize.height - 2))
		path.addLine(to: CGPoint(x: midX, y: bubbleSize.height + Self.tailHeight))
		path.addLine(to: CGPoint(x: midX + Self.tailWidth / 2, y: bubbleSize.height - 2))
		path.close()
		tail.path = path.cgPath

		frame.size = CGSize(width: bubbleSize.width, height: bubbleSize.height + Self.tailHeight)
		// The view is centered on the coordinate; lift it so the tail's tip meets the pin.
		centerOffset = CGPoint(x: 0, y: -(frame.height / 2 + Self.pinRadius))
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		guard window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
		alpha = 0
		transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
		UIView.animate(withDuration: 0.3) {
			self.alpha = 1
			self.transform = .identity
		}
	}

	override var canBecomeFocused: Bool { false }
}
