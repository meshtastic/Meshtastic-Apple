import Foundation
import RegexBuilder

final class CommonRegex {
	static let coordinateRegex = Regex {
		Capture {
			Regex {
				"lat="
				OneOrMore(.digit)
			}
		}

		Capture {
			" "
		}

		Capture {
			Regex {
				"long="
				OneOrMore(.digit)
			}
		}
	}
		.anchorsMatchLineEndings()
}
