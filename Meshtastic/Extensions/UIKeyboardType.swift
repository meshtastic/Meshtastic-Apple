//
//  UIKeyboard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 1/7/26.
//
import UIKit

extension UIKeyboardType {
	static var emoji: UIKeyboardType {
		return UIKeyboardType(rawValue: 124) ?? .default
	}
}
