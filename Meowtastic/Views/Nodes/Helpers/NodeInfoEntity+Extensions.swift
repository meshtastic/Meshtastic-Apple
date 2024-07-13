import Foundation
import MeshtasticProtobufs
import SwiftUI

extension NodeInfoEntity {
	var color: Color {
		Color(
			UIColor(hex: UInt32(num))
		)
	}
}
