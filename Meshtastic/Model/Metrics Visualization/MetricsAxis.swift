//
//  MetricsAxis.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//

import Foundation

/// The Y axis a chart series is drawn against. Series with the same axis share a chart; series
/// on different axes get charts of their own, so a reading in the thousands never flattens one in
/// single digits (design#53 requirement 5).
struct MetricsAxis: Hashable {

	enum Scale: Hashable {
		/// Padded around the data, never pinned to zero, at least `minimumSpan` tall.
		case padded(minimumSpan: Float)
		/// Starts at zero, with a small offset below so a zero reading sits off the bottom edge.
		case zeroBased
		/// A fixed range that grows only when a reading falls outside it.
		case fixed(ClosedRange<Float>)
		/// A window of fixed height that starts at `preferred` and slides to keep every reading in
		/// view, widening to the data only when the readings span more than `width`.
		case window(width: Float, preferred: ClosedRange<Float>)
	}

	let id: String
	let scale: Scale

	static let temperature = MetricsAxis(id: "temperature", scale: .padded(minimumSpan: 10))
	static let percent = MetricsAxis(id: "percent", scale: .fixed(0...100))
	/// 100 hPa wide, 950–1050 near sea level, as Android does (design#53 requirement 4).
	static let pressure = MetricsAxis(id: "pressure", scale: .window(width: 100, preferred: 950...1050))

	static func zeroBased(_ id: String) -> MetricsAxis {
		MetricsAxis(id: id, scale: .zeroBased)
	}

	static func padded(_ id: String, minimumSpan: Float = 1) -> MetricsAxis {
		MetricsAxis(id: id, scale: .padded(minimumSpan: minimumSpan))
	}

	/// The Y range to draw `values` against.
	func range(for values: [Float]) -> ClosedRange<Float> {
		let finite = values.filter(\.isFinite)
		guard let low = finite.min(), let high = finite.max() else {
			switch scale {
			case .fixed(let range): return range
			case .window(_, let preferred): return preferred
			case .padded, .zeroBased: return 0...100
			}
		}
		switch scale {
		case .padded(let minimumSpan):
			let span = Swift.max(high - low, minimumSpan)
			let center = (low + high) / 2
			let margin = span * 0.1
			return (center - span / 2 - margin)...(center + span / 2 + margin)
		case .zeroBased:
			let lower = Swift.min(0, low)
			let span = Swift.max(high - lower, 1)
			let offset = lower == 0 ? span * 0.05 : span * 0.1
			return (lower - offset)...(high + span * 0.1)
		case .fixed(let range):
			return Swift.min(range.lowerBound, low)...Swift.max(range.upperBound, high)
		case .window(let width, let preferred):
			if high - low > width {
				let margin = (high - low) * 0.05
				return (low - margin)...(high + margin)
			}
			if low < preferred.lowerBound {
				return low...(low + width)
			}
			if high > preferred.upperBound {
				return (high - width)...high
			}
			return preferred
		}
	}
}
