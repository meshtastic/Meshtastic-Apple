//
//  MapSnrLabel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/15/26.
//

import SwiftUI

/// An SNR value as a small pill in the SNR color, placed on trace route legs and node links on
/// the map.
struct MapSnrLabel: View {
	let snr: Float
	let color: Color

	var body: some View {
		Text("\(snr.formatted(.number.precision(.fractionLength(1)))) dB")
			.font(.system(size: 10, weight: .bold))
			.monospacedDigit()
			.foregroundStyle(.black)
			.padding(.horizontal, 5)
			.padding(.vertical, 1.5)
			.background(Capsule().fill(color))
			.overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.75))
			.shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
			.fixedSize()
			.accessibilityHidden(true)
	}
}
