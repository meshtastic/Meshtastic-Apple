//
//  CommonRegex.swift
//  Meshtastic
//
//  Created by Ben Meadors on 7/2/24.
//

import Foundation
import RegexBuilder

class CommonRegex {
	static let COORDS_REGEX = Regex {
			Capture {
			 Regex {
				 "lat="
				 OneOrMore(.digit)
			 }
		 }
		 Capture {" "}
		 Capture {
			 Regex {
				 "long="
				 OneOrMore(.digit)
			 }
		 }
	 }
	 .anchorsMatchLineEndings()
}
