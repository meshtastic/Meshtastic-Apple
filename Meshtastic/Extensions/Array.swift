//
//  Array.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 4/27/23.
//

import Foundation


extension Array {
	func mapNonNils<T, E>(_ transform: (E) -> T) -> [T] where Element == Optional<E> {
		return self.compactMap { element in
			guard let element = element else { return nil }
			return transform(element)
		}
	}
}
