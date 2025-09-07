//
//  Bool.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/6/25.

extension Bool {
	
	 static var iOS18: Bool {
		 guard #available(iOS 18, *) else {
			 return true
		 }
		 return false
	 }
	
	static var masOS15: Bool {
		guard #available(macOS 15, *) else {
			return true
		}
		return false
	}
	
	static var os26: Bool {
		guard #available(iOS 26, macOS 26, *) else {
			return true
		}
		return false
	}
 }
