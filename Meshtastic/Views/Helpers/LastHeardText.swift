import SwiftUI
//
//  LastHeardText.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/25/22.
//
struct LastHeardText: View {
	var lastHeard: Date?
	
	let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())

	var body: some View {
		if (lastHeard != nil && lastHeard! >= sixMonthsAgo!){
			
			Text("Heard: \(lastHeard!, style: .relative) ago")
			
		} else {
			
			Text("Unknown Age")
		}
	}
}
