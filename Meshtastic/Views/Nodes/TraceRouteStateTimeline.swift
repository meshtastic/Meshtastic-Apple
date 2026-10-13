//
//  TraceRouteStateTimeline.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import SwiftUI

/// Redraws its content while a trace route is waiting for a response, so the row moves from
/// waiting to no response without anything else changing. Other routes draw once.
struct TraceRouteStateTimeline<Content: View>: View {
	let route: TraceRouteEntity
	@ViewBuilder let content: (Date) -> Content

	var body: some View {
		if route.state() == .pending {
			TimelineView(.periodic(from: .now, by: 10)) { timeline in
				content(timeline.date)
			}
		} else {
			content(.now)
		}
	}
}
