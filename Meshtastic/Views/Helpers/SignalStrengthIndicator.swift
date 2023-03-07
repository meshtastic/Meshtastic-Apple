/*
* Copyright (c) 2022, Nordic Semiconductor
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
* are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice, this
*    list of conditions and the following disclaimer in the documentation and/or
*    other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its contributors may
*    be used to endorse or promote products derived from this software without
*    specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

import Foundation
import SwiftUI

struct SignalStrengthIndicator: View {
	let signalStrength: SignalStrength

	var body: some View {
		HStack {
			ForEach(0..<3) { bar in
				RoundedRectangle(cornerRadius: 3)
					.divided(amount: (CGFloat(bar) + 1) / CGFloat(3))
					.fill(getColor().opacity(bar <= signalStrength.rawValue ? 1 : 0.3))
					.frame(width: 8, height: 30)
			}
		}
	}

	private func getColor() -> Color {
		switch signalStrength {
		case .weak:
			return Color.red
		case .normal:
			return Color.yellow
		case .strong:
			return Color.green
		}
	}
}

struct Divided<S: Shape>: Shape {
	var amount: CGFloat // Should be in range 0...1
	var shape: S
	func path(in rect: CGRect) -> Path {
		shape.path(in: rect.divided(atDistance: amount * rect.height, from: .maxYEdge).slice)
	}
}

extension Shape {
	func divided(amount: CGFloat) -> Divided<Self> {
		return Divided(amount: amount, shape: self)
	}
}

enum SignalStrength: Int {
	case weak = 0
	case normal = 1
	case strong = 2
}
